#!/usr/bin/env bash
# B06: physical-iPhone evidence for the frozen B03 journey. bench/ is read-only.
# Process discovery: xcrun devicectl device info processes --device UDID --json-output FILE
# devicectl identifies the target PID; it is NOT a source for RSS/CPU.
# Numerical telemetry: xcrun xctrace record/export of the device's Instruments data.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
UDID="${FEEDMINE_BENCH_DEVICE_UDID:-}"
HOST="${FEEDMINE_BENCH_TRANSPORT_HOST:-}"
LIMIT="${FEEDMINE_B06_TIME_LIMIT:-45m}"
VALIDATE=0
LIMIT_EXPLICIT=0
usage() {
  echo 'usage: bash scripts/b06-evidence.sh --udid <physical-UDID> --host <MAC_IP>:8757 [--validate] [--time-limit 60s|45m|1h]' >&2
  exit 2
}
while (( $# )); do
  case "$1" in
    --udid) (( $# >= 2 )) || usage; UDID="$2"; shift 2 ;;
    --host) (( $# >= 2 )) || usage; HOST="$2"; shift 2 ;;
    --time-limit) (( $# >= 2 )) || usage; LIMIT="$2"; LIMIT_EXPLICIT=1; shift 2 ;;
    --validate) VALIDATE=1; shift ;;
    *) usage ;;
  esac
done
if [[ "$VALIDATE" == 1 && "$LIMIT_EXPLICIT" == 0 && -z "${FEEDMINE_B06_TIME_LIMIT:-}" ]]; then
  LIMIT="60s"
fi
[[ "$LIMIT" =~ ^[1-9][0-9]*(s|m|h)$ ]] || { echo 'REFUSED: time limit must be a positive duration with s/m/h suffix' >&2; usage; }
[[ -n "$UDID" && -n "$HOST" ]] || { echo 'REFUSED: UDID and Mac host:port required' >&2; exit 2; }
[[ "$UDID" =~ ^[A-Za-z0-9-]+$ && "$HOST" =~ ^[A-Za-z0-9.-]+:8757$ ]] || usage
for cmd in xcrun xcodebuild python3 git; do
  command -v "$cmd" >/dev/null || { echo "REFUSED: missing $cmd" >&2; exit 2; }
done
export FEEDMINE_BENCH_DEVICE_UDID="$UDID" FEEDMINE_BENCH_TRANSPORT_HOST="$HOST"
python3 - "$ROOT" "$UDID" "$HOST" "$LIMIT" "$VALIDATE" <<'PY'
import datetime as dt
import json
import math
import os
import pathlib
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

root, udid, host = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
time_limit, validate = sys.argv[4], sys.argv[5] == '1'
record_seconds = int(time_limit[:-1]) * {'s':1, 'm':60, 'h':3600}[time_limit[-1]]
if validate and record_seconds > 180:
    raise SystemExit('REFUSED: --validate must use a capture <=180s (default 60s)')
run_root = root / 'bench/run'
existing = {p.name for p in run_root.iterdir() if p.is_dir()} if run_root.exists() else set()
replay = 'bash scripts/b06-evidence.sh --udid ' + shlex.quote(udid) + ' --host ' + shlex.quote(host) + (' --validate' if validate else '') + ' --time-limit ' + shlex.quote(time_limit)
journey = ['bash', 'scripts/run-discovery-benchmark.sh', '--gate', 'B03', '--profile', 'A', '--full-trace']
app_id = 'com.feedmine.development.benchmark'
now = lambda: dt.datetime.now(dt.timezone.utc).isoformat()
# Template chains are read from the installed toolchain. The historical iOS
# 'Energy Log' template is absent from Xcode 26.6 (17F113); 'Power Profiler' is
# the documented successor (iOS/iPadOS only). Its exported tables carry per-process
# Power Impact relative indices and device thermal state, but no energy-labelled
# column and no Joules, so B06 declares that gap instead of relabelling power as
# energy. The declaration is accepted by --validate only while the installed
# toolchain still shows Energy Log missing AND the successor template present.
TEMPLATE_CHAINS = {'hitches': ('Animation Hitches',),
                   'resources': ('Activity Monitor',),
                   'energy': ('Energy Log', 'Power Profiler')}
ENERGY_GAP_CODE = 'ENERGY_TEMPLATE_ENERGY_LOG_ABSENT_SUCCESSOR_HAS_NO_ENERGY_METRIC'
ENERGY_GAP_REASON = ("Template 'Energy Log' absent from xctrace list templates; "
                     "successor 'Power Profiler' exports per-process Power Impact "
                     "relative indices and device thermal state, but no per-process "
                     "energy column (no Joules), so no energy measurement is bindable "
                     "on this toolchain")

def write_json(p, obj):
    p.write_text(json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + '\n')

def command(args, log, timeout=150):
    """Never hide subprocess exit codes. Retain exact invocation and combined output."""
    cmd = shlex.join([str(a) for a in args])
    try:
        r = subprocess.run(args, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, timeout=timeout)
        log.write_text('$ ' + cmd + '\n' + r.stdout + '\nexit=' + str(r.returncode) + '\n')
        return r
    except (subprocess.TimeoutExpired, OSError) as err:
        log.write_text('$ ' + cmd + '\nERROR: ' + str(err) + '\n')
        raise RuntimeError(f'{cmd}: {err}') from err

def device_processes(scratch):
    path = scratch / 'devicectl-processes.json'
    if path.exists():
        path.unlink()  # avoid interpreting a stale JSON file as a fresh sample
    args = ['xcrun', 'devicectl', 'device', 'info', 'processes', '--device', udid,
            '--json-output', str(path)]
    result = command(args, scratch/'devicectl.log', timeout=35)
    if result.returncode or not path.exists():
        raise RuntimeError(f'devicectl process discovery failed ({result.returncode})')
    return json.loads(path.read_text())['result']['runningProcesses']

def target_pids(processes, container=None):
    found = []
    for item in processes:
        executable = str(item.get('executable', ''))
        if not re.search(r'/FeedMine\.app/FeedMine$', executable):
            continue
        # Only the benchmark app's own container. The owner's TestFlight app and the product development build
        # also run a `FeedMine.app/FeedMine`, and refusing because the reader happens to be open is not this
        # gate's business (measured 2026-10-20: three runs refused while com.feedmine.app was in the foreground).
        if container and not executable.startswith(container):
            continue
        found.append(int(item['processIdentifier']))
    return sorted(set(found))

def app_container(scratch, bundle_id):
    """The installed container URL of the benchmark app, or None when it is not installed."""
    path = scratch / 'apps-preflight.json'
    result = command(['xcrun', 'devicectl', 'device', 'info', 'apps', '--device', udid,
                      '--json-output', str(path)], scratch/'devicectl-apps.log', timeout=60)
    if result.returncode or not path.exists():
        return None
    try:
        apps = json.loads(path.read_text())['result']['apps']
    except (ValueError, KeyError):
        return None
    for app in apps:
        if app.get('bundleIdentifier') == bundle_id:
            return str(app.get('url') or app.get('installationURL') or '') or None
    return None

def missing(reason, commands=None):
    ans = {'status':'NOT_MEASURED', 'reason':reason}
    if commands:
        ans['commands_attempted'] = commands
    return ans

# An export is <trace-query-result><schema><col>...<mnemonic>..</col>...</schema>
# <row><sample-time fmt="00:00.039.455">...</sample-time> ...</row>.
# Detect schema and column semantics *from the trace itself*, not assumed column positions.
def parse_table(path):
    document = ET.parse(path).getroot()
    schema = document.find('.//schema')
    if schema is None:
        raise ValueError('XML export has no column schema')
    columns = []
    for col in schema.findall('./col'):
        meta = {child.tag.lower(): (child.text or '').strip() for child in col}
        columns.append({'mnemonic': meta.get('mnemonic',''), 'name':meta.get('name',''),
                        'type':meta.get('type',''), 'unit':meta.get('unit',''),
                        'metadata':meta})
    if not columns:
        raise ValueError('XML export has no columns')
    refs = {elem.get('id'):elem for elem in document.iter() if elem.get('id')}
    rows = []
    for row in document.findall('.//row'):
        cells = []
        for element in row:
            obj = refs.get(element.get('ref'), element)
            raw = (obj.text or '').strip()
            display = obj.get('fmt', '').strip() or raw
            cells.append({'tag':element.tag.lower(), 'display':display, 'raw':raw,
                          'metadata':dict(obj.attrib)})
        if len(cells)==len(columns):
            rows.append(cells)
    return columns, rows

def column_text(c):
    return ' '.join([c['mnemonic'], c['name'], c['type'], c['unit']]).lower().replace('_','-')

def classified(columns, schema=''):
    """Infer roles from exported column semantics plus TOC table context."""
    roles = {}
    for i, col in enumerate(columns):
        label = column_text(col)
        metric = (col['mnemonic'] + ' ' + col['name']).lower().replace('_','-')
        if re.search(r'\b(process|pid|application)\b', metric): roles.setdefault('process', []).append(i)
        if re.search(r'\b(start|timestamp|time|sample-time)\b', metric) and not re.search('duration|elapsed|total', metric):
            roles.setdefault('time', []).append(i)
        if ('resident' in metric or re.search(r'\brss\b', metric)) and not ('virtual' in metric):
            roles.setdefault('rss', []).append(i)
        if 'footprint' in metric and ('physical' in metric or 'memory' in metric):
            roles.setdefault('memory', []).append(i)
        if 'cpu' in metric and ('percent' in metric or 'usage' in metric or 'utilization' in metric or '%' in label):
            roles.setdefault('cpu', []).append(i)
        if ('hitch' in metric and ('duration' in metric or 'latency' in metric)) or (
            'hitch' in schema.lower() and re.search(r'\b(duration|latency)\b',metric)):
            roles.setdefault('hitch_duration', []).append(i)
        if 'energy' in metric and ('impact' in metric or 'usage' in metric or 'consumption' in metric):
            if 'impact' in metric: roles.setdefault('energy_impact', []).append(i)
            else: roles.setdefault('energy', []).append(i)
        if re.search(r'\bthermal\b', metric) and re.search(r'state|level|severity',metric):
            roles.setdefault('thermal', []).append(i)
    return roles

UNITS = {'b':1, 'byte':1, 'bytes':1, 'kb':1000, 'kib':1024, 'mb':10**6,
         'mib':2**20, 'gb':10**9, 'gib':2**30, 'tb':10**12, 'tib':2**40}

def numeric(cell, col, kind):
    """Only numeric with explicit units; raw values never silently imply bytes or percent."""
    for value in (cell['display'], cell['raw']):
        match = re.fullmatch(r'\s*([+-]?\d+(?:\.\d+)?)\s*([A-Za-z%/]+)\s*',value)
        if not match:
            continue
        quantity,unit = float(match.group(1)),match.group(2).lower()
        if not math.isfinite(quantity): continue
        if kind=='cpu' and unit in ('%', 'percent'): return quantity
        if kind in ('rss','memory') and unit in UNITS: return quantity * UNITS[unit]
        if kind=='energy' and unit in ('j','mj','uj','wh','mwh'):
            return quantity * {'j':1,'mj':1e-3,'uj':1e-6,'wh':3600,'mwh':3.6}[unit]
    # Energy Impact is a relative index, NOT Joules. Only accept it under
    # an explicitly energy-impact column; do not relabel it as physical energy.
    if kind=='energy_impact' and 'impact' in (col['mnemonic']+' '+col['name']).lower():
        if re.fullmatch(r'[+-]?\d+(?:\.\d+)?', cell['display']):
            return float(cell['display'])
        if re.fullmatch(r'[+-]?\d+(?:\.\d+)?', cell['raw']):
            return float(cell['raw'])
    # Some xctrace schemas export raw integer bytes or a raw numeric CPU percent.
    # Accept it ONLY when the column itself explicitly declares its unit.
    unit = col['unit'].lower().strip() or col['metadata'].get('units','').lower().strip()
    value = cell['raw']
    if re.fullmatch(r'[+-]?\d+(?:\.\d+)?', value):
        n=float(value)
        if kind=='cpu' and unit in ('%', 'percent'): return n
        if kind in ('rss','memory') and unit in UNITS: return n*UNITS[unit]
        if kind=='energy' and unit in ('j','mj','uj','wh','mwh'):
            return n * {'j':1,'mj':1e-3,'uj':1e-6,'wh':3600,'mwh':3.6}[unit]
    return None

def seconds(cell, col):
    # Examples: 00:00.039.455 (mm:ss.mmm.uuu), 00:12:03.123, 33.4s.
    for value in (cell['display'], cell['raw']):
        m = re.fullmatch(r'(\d+):(\d{2})\.(\d{3})\.(\d{3})',value)
        if m: return int(m[1])*60 + int(m[2]) + int(m[3])/1e3 + int(m[4])/1e6
        m = re.fullmatch(r'(\d+):(\d{2}):(\d{2})(?:\.(\d+))?',value)
        if m: return int(m[1])*3600 + int(m[2])*60 + int(m[3]) + float('0.'+(m[4] or '0'))
        m = re.fullmatch(r'(\d+(?:\.\d+)?)\s*(s|ms|us|ns)',value)
        if m: return float(m[1])*{'s':1,'ms':1e-3,'us':1e-6,'ns':1e-9}[m[2]]
    # As for metrics, a raw timestamp needs an explicit unit in column metadata.
    unit = col['unit'].lower() or col['metadata'].get('units','').lower()
    if re.fullmatch(r'\d+(?:\.\d+)?',cell['raw']) and unit in ('s','ms','us','ns'):
        return float(cell['raw'])*{'s':1,'ms':1e-3,'us':1e-6,'ns':1e-9}[unit]
    return None

def belongs(cell, pid):
    text = cell['display']+' '+cell['raw']
    return bool(re.search(r'(?<!\d)'+re.escape(str(pid))+r'(?!\d)',text)) or bool(
        re.search(r'(?<!\w)FeedMine(?:\s|\(|$)',text))

def samples_from_table(columns,rows,roles,kind,pid,app_scoped):
    if kind not in roles: return [], 'No '+kind+' semantic column in export'
    pcols=roles.get('process', [])
    if not pcols and not app_scoped:
        return [], 'No process column; export is not provably app-only'
    if not pcols and app_scoped:
        return [], 'No process attribution column; refusing to attribute global rows to app'
    if len(roles[kind]) != 1:
        return [], 'Ambiguous '+kind+' columns: '+str(roles[kind])
    k=roles[kind][0]
    timecols=roles.get('time',[])
    observed=[]
    for row in rows:
        if not any(belongs(row[i],pid) for i in pcols): continue
        val=numeric(row[k],columns[k],kind)
        if val is None: continue
        t=next((seconds(row[i],columns[i]) for i in timecols
                if seconds(row[i],columns[i]) is not None),None)
        observed.append((t,val))
    return observed, ('No process-attributed values with explicit '+kind+' units' if not observed else None)

def summarize(values, unit):
    if not values: return missing('No verified samples')
    nums=[v for _,v in values]
    result={'status':'MEASURED','unit':unit,'samples':len(nums),'peak':max(nums),
            'minimum':min(nums),'mean':sum(nums)/len(nums)}
    # Time-relative trend AFTER warm-up. Never claim a leak from merely two points.
    timed=sorted((t,v) for t,v in values if t is not None)
    post=[(t,v) for t,v in timed if timed and t >= timed[0][0]+300]
    if len(post)>=6 and post[-1][0]-post[0][0]>=300:
        width=max(2,len(post)//4)
        initial=sum(v for _,v in post[:width])/width
        final=sum(v for _,v in post[-width:])/width
        result['post_warmup_trend']={'status':'MEASURED','early_mean':initial,
             'late_mean':final,'delta':final-initial,'unit':unit,
             'warmup_seconds':300,'relative_to':'start of Instruments trace'}
    else:
        result['post_warmup_trend']=missing('Insufficient timestamped samples over >=5 min after 300s warm-up')
    return result

def measured_swipes(logfile):
    cmd='parse actual XCTest step timestamps from '+str(logfile)
    if not logfile.exists(): return missing('B03 XCTest step log absent', [cmd])
    # XCTest emits: t = 1358.20s    Swipe up ... . The phase log includes onboarding.
    steps=[]
    for line in logfile.read_text(errors='replace').splitlines():
        m=re.search(r'\bt\s*=\s*([0-9]+(?:\.[0-9]+)?)s\b.*\bSwipe\s+up\b',line,re.I)
        if m: steps.append(float(m[1]))
    if len(steps)<2 or steps[-1] <= steps[0]:
        return missing(f'Expected >=2 monotonic Swipe up step timestamps, got {len(steps)}', [cmd])
    if any(b<a for a,b in zip(steps,steps[1:])):
        return missing('B03 XCTest swipe timestamps are non-monotonic', [cmd])
    return {'status':'MEASURED','elapsed_seconds_first_to_last_swipe':steps[-1]-steps[0],
            'first_step_seconds':steps[0],'last_step_seconds':steps[-1],
            'swipe_steps':len(steps),'scope':'observed swipe window; excludes onboarding and unlogged last gesture duration',
            'command':cmd}

status={'status':'NOT_RUN','started_at':now(),'device_udid':udid,
        'transport_host':host,'app_identifier':app_id,'rerun':replay,
        'b03_driver_command':journey,
        'mode':'SCHEMA_VALIDATION' if validate else 'CERTIFICATION_EVIDENCE',
        'is_gate_evidence':False, 'record_time_limit':time_limit,
        'record_duration_seconds':record_seconds,
        'metrics':{key:missing('Measurement not yet attempted') for key in
                   ('rss','cpu','memory','energy','thermal','hitches','scroll_time','peaks_and_trends')},
        'recordings':{},'errors':[],'templates_used':{},'declared_absences':[]}
out=None
runner=None
streams={}
recordings={}
pid=None
validation_deadline=None
validation_started=None
validation_stopped_driver=False
binding_proofs={key:[] for key in ('rss','cpu','memory','energy','energy_impact','thermal','hitches','scroll_time')}
errors=status['errors']
with tempfile.TemporaryDirectory(prefix='feedmine-b06-control-') as d:
    temp=pathlib.Path(d)
    try:
        initial=target_pids(device_processes(temp), app_container(temp, app_id))
        if initial: raise RuntimeError('REFUSED: the benchmark app is already running on device: '+str(initial))
        tmpl=command(['xcrun','xctrace','list','templates'],temp/'templates.log',timeout=45)
        if tmpl.returncode: raise RuntimeError('xctrace list templates failed')
        # Human-readable names from installed Xcode; not static schema names.
        available={line.strip().strip('"') for line in tmpl.stdout.splitlines()}
        # Energy is recorded with the installed `Power Profiler` template: `Energy Log` does not exist in
        # Xcode 26.6 (`xcrun xctrace list templates`, 2026-10-20), and the 2026-10-20T050511Z run reported
        # energy NOT_MEASURED for exactly that reason. A template that does not exist cannot measure anything.
        requested={'hitches':'Animation Hitches','resources':'Activity Monitor','energy':'Power Profiler'}
        if requested['hitches'] not in available:
            raise RuntimeError('Animation Hitches template unavailable; cannot record required B06 frames')
        for key,names in TEMPLATE_CHAINS.items():
            chosen=next((name for name in names if name in available),None)
            status['recordings'][key]={'template':chosen,'template_candidates':list(names),
                'template_source':None if chosen is None else
                    ('PRIMARY' if chosen==names[0] else 'SUCCESSOR'),
                'status':'NOT_MEASURED',
                'reason':None if chosen else 'No candidate template present: '+', '.join(names)}
            status['templates_used'][key]={'template':chosen,
                'source':status['recordings'][key]['template_source'],
                'candidates_tried':list(names)}
        stream=(temp/'journey.log').open('w')
        runner=subprocess.Popen(journey,cwd=root,stdout=stream,stderr=subprocess.STDOUT,
                                 start_new_session=True)
        deadline=time.monotonic()+120
        while time.monotonic()<deadline:
            new=[p for p in run_root.iterdir() if p.is_dir() and p.name not in existing] if run_root.exists() else []
            if len(new)>1: raise RuntimeError('Multiple benchmark run directories appeared; cannot attribute')
            if len(new)==1:
                out=new[0]/'b06'
                out.mkdir(exist_ok=False)
                status['run_directory']=str(new[0]);break
            if runner.poll() is not None:
                raise RuntimeError('B03 exited before creating its evidence directory')
            time.sleep(1)
        if out is None: raise RuntimeError('B03 did not create a run directory within 120 seconds')
        status['source_commit']=command(['git','rev-parse','HEAD'],out/'commit-command.log').stdout.strip()
        status['xcode_version']=command(['xcodebuild','-version'],out/'xcode-version.log').stdout.strip()
        shutil.copy(temp/'templates.log',out/'templates.log')
        print('B06 package:',out,flush=True)
        print('MODE:', 'SCHEMA VALIDATION ONLY — NOT GATE EVIDENCE' if validate else 'CERTIFICATION EVIDENCE — NOT PASS',flush=True)
        attach_deadline=time.monotonic()+360 if validate else None
        while runner.poll() is None:
            if validate and pid is None and time.monotonic()>=attach_deadline:
                raise RuntimeError('Validation could not attach to FeedMine within 6 minutes of run setup')
            found=target_pids(device_processes(temp), app_container(temp, app_id))
            with (out/'pid-samples.jsonl').open('a') as f:
                f.write(json.dumps({'at':now(),'pids':found})+'\n')
            if len(found)>1: raise RuntimeError('Ambiguous target process PIDs: '+str(found))
            if pid is not None and found and found[0]!=pid:
                raise RuntimeError(f'FeedMine process restarted: {pid}->{found[0]}; instrumentation incomplete')
            if pid is None and found:
                pid=found[0]
                status['attached_at']=now()
                status['target_pid']=pid
                for key,spec in status['recordings'].items():
                    if spec['reason'] is not None: continue
                    dest=out/(key+'.trace')
                    args=['xcrun','xctrace','record','--template',spec['template'],
                          '--device',udid,'--attach',str(pid),'--time-limit',time_limit,
                          '--no-prompt','--output',str(dest)]
                    spec['command']=shlex.join(args)
                    spec['trace']=str(dest)
                    output=(out/(key+'.record.log')).open('w')
                    try:
                        proc=subprocess.Popen(args,cwd=root,stdout=output,stderr=subprocess.STDOUT,
                                              start_new_session=True)
                    except OSError as err:
                        output.close()
                        spec['reason']=f'Record command could not launch: {err}'
                        errors.append(spec['reason'])
                        continue
                    recordings[key]=proc
                    streams[key]=output
                    spec['status']='RECORDING'
                    spec['started_at']=now()
                if validate:
                    validation_started=time.monotonic()
                    # The recorders start collecting after their startup handshake.
                    # Allow a short sealing margin; never wait for the 30m B03.
                    validation_deadline=validation_started+record_seconds+90
                    status['validation_capture_started_at']=now()
                print('Attached to iPhone process PID',pid,flush=True)
            # The short probe deliberately interrupts B03. It is not gate evidence.
            if validate and validation_deadline is not None:
                # Normal completion of every xctrace --time-limit recorder is the
                # preferred stop condition; a hard 90s seal/startup allowance is
                # only a watchdog, never evidence of a successful measurement.
                all_recorders_ended=(len(recordings)==len([v for v in status['recordings'].values()
                                  if v.get('reason') is None]) and all(
                                  proc.poll() is not None for proc in recordings.values()))
                elapsed=time.monotonic()-validation_started
                if (all_recorders_ended and elapsed>=record_seconds-5) or time.monotonic()>=validation_deadline:
                    validation_stopped_driver=True
                    status['validation_capture_ended_at']=now()
                    status['validation_wall_seconds']=elapsed
                    if time.monotonic()>=validation_deadline and not all_recorders_ended:
                        errors.append('Validation xctrace did not seal before short-capture watchdog')
                    if runner.poll() is None:
                        os.killpg(runner.pid, signal.SIGINT)
                    break
            # An early exit is incomplete, except normal completion at the short limit.
            for key,proc in recordings.items():
                if proc.poll() is not None and status['recordings'][key]['status']=='RECORDING':
                    at_horizon=(validate and validation_started is not None and
                                time.monotonic() >= validation_started+record_seconds-5 and
                                proc.returncode==0)
                    if not at_horizon:
                        spec=status['recordings'][key]
                        spec['status']='PARTIAL'
                        spec['reason']=f'Recorder exited before expected stop (exit {proc.returncode})'
                        errors.append(key+': '+spec['reason'])
            sleep_seconds=(3 if pid is None else
                           min(3,max(0.2,validation_deadline-time.monotonic()))
                           if validate and validation_deadline is not None else 30)
            time.sleep(sleep_seconds)
        status['b03_exit_code']=runner.wait(timeout=45 if validate else None)
        status['journey_finished_at']=now()
        stream.close()
        shutil.copy(temp/'journey.log',out/'journey.log')
        if pid is None: errors.append('No FeedMine PID detected while B03 ran')
        if not validate and status['b03_exit_code']!=0: errors.append('B03 wrapper exited nonzero: '+str(status['b03_exit_code']))
        if validate and not validation_stopped_driver: errors.append('Validation driver terminated before the configured capture window finished')
        # Stop with SIGINT, then require completed export and valid exit before RECORDED.
        for key,proc in recordings.items():
            if proc.poll() is None: os.killpg(proc.pid,signal.SIGINT)
        for key,proc in recordings.items():
            spec=status['recordings'][key]
            timed_out=False
            try: rc=proc.wait(timeout=120)
            except subprocess.TimeoutExpired:
                timed_out=True
                os.killpg(proc.pid,signal.SIGTERM)
                rc=proc.wait(timeout=30)
            streams[key].close()
            spec['exit_code']=rc
            spec['ended_at']=now()
            trace=pathlib.Path(spec['trace'])
            if not trace.exists() or not any(trace.iterdir()):
                spec.update(status='NOT_MEASURED',reason=f'xctrace produced no nonempty trace (exit={rc})')
                errors.append(key+': '+spec['reason']); continue
            if timed_out or rc!=0 or spec['status']=='PARTIAL':
                spec.update(status='PARTIAL', reason=spec.get('reason') or f'xctrace exited {rc}; trace potentially incomplete')
                errors.append(key+': '+spec['reason'])
            else:
                spec.update(status='RECORDED',reason=None)
            toc=out/(key+'.toc.xml')
            args=['xcrun','xctrace','export','--input',str(trace),'--toc','--output',str(toc)]
            spec['toc_command']=shlex.join(args)
            result=command(args,out/(key+'.toc.log'),timeout=180)
            if result.returncode or not toc.exists() or not toc.stat().st_size:
                spec.update(status='PARTIAL',reason=f'TOC export failed (exit={result.returncode})')
                errors.append(key+': '+spec['reason']); continue
            spec['tables']=[]
            tree=ET.parse(toc).getroot()
            for run in tree.findall('./run'):
                number=run.get('number')
                if not number: continue
                for table in run.findall('./data/table'):
                    schema=table.get('schema')
                    if not schema: continue
                    # Export every TOC table. Unknown schema names may contain
                    # relevant columns, so do not hardcode a schema-name allowlist.
                    xpath=f'/trace-toc/run[@number="{number}"]/data/table[@schema="{schema}"]'
                    safe_schema=re.sub(r'[^A-Za-z0-9_.-]+','_',schema)
                    target=out/(key+'.'+str(number)+'.'+safe_schema+'.xml')
                    args=['xcrun','xctrace','export','--input',str(trace),'--xpath',xpath,
                          '--output',str(target)]
                    item={'run':number,'schema':schema,'command':shlex.join(args), 'xml':str(target)}
                    result=command(args,out/(key+'.'+str(number)+'.'+safe_schema+'.log'),timeout=240)
                    if result.returncode or not target.exists() or not target.stat().st_size:
                        item['status']='EXPORT_FAILED'
                        item['reason']='xctrace export exited '+str(result.returncode)
                        errors.append(key+': '+item['reason']+' '+schema)
                    else:
                        item['status']='EXPORTED'
                    spec['tables'].append(item)
        # Parse only exported tables; process identity is compulsory for process metrics.
        reading={'rss':[], 'cpu':[], 'memory':[], 'energy':[], 'energy_impact':[]}
        metric_commands={key:[] for key in ('rss','cpu','memory','energy','energy_impact','thermal','hitches')}
        status['exported_schema_columns']=[]
        hitch_events_by_schema={}
        hitch_valid_schemas=set()
        table_time_spans={}
        thermal_rows=[]
        for key,spec in status['recordings'].items():
            for item in spec.get('tables',[]):
                schema=item['schema'].lower()
                if item['status']!='EXPORTED':continue
                try: cols,rows=parse_table(pathlib.Path(item['xml']))
                except (ValueError,ET.ParseError) as err:
                    errors.append(f'Unparsable export {schema}: {err}');continue
                item['columns']=cols
                item['row_count']=len(rows)
                roles=classified(cols,item['schema'])
                item['roles']=roles
                status['exported_schema_columns'].append({
                    'instrument':key, 'schema':item['schema'], 'run':item['run'],
                    'columns':cols, 'roles':roles, 'export_command':item['command']})
                candidate_times=[seconds(row[i],cols[i]) for row in rows for i in roles.get('time',[])
                                 if seconds(row[i],cols[i]) is not None]
                if len(candidate_times)>=2:
                    table_time_spans[schema]=[min(candidate_times),max(candidate_times)]
                if pid is not None:
                    for target in reading:
                        if target not in roles: continue
                        metric_commands[target].append(item['command'])
                        observed,reason=samples_from_table(cols,rows,roles,target,pid,False)
                        reading[target].extend(observed)
                        if observed:
                            indices=roles.get('process',[])+roles.get(target,[])+roles.get('time',[])
                            binding_proofs[target].append({
                                'instrument':key, 'schema':item['schema'],
                                'columns':[cols[i] for i in dict.fromkeys(indices)],
                                'sample_count':len(observed), 'export_command':item['command']})
                        if reason: item.setdefault('unavailable',{})[target]=reason
                if 'thermal' in roles:
                    pcols=roles.get('process',[])
                    # Thermal state is DEVICE-level. Report device attribution, never process thermal.
                    if not pcols:
                        for row in rows:
                            for ci in roles['thermal']:
                                val=row[ci]['display']
                                if val:
                                    thermal_rows.append({'state':val,'scope':'device', 'schema':schema})
                                    metric_commands['thermal'].append(item['command'])
                                    binding_proofs['thermal'].append({
                                        'instrument':key, 'schema':item['schema'],
                                        'columns':[cols[ci]], 'sample_count':1,
                                        'export_command':item['command']})
                if 'hitch_duration' in roles and 'summary' not in schema:
                    pcols=roles.get('process',[])
                    # Only explicit positive hitch duration constitutes a hitch event;
                    # do NOT count all render intervals or a processless global summary.
                    dcols=roles.get('hitch_duration',[])
                    if pcols and len(dcols)==1 and pid is not None:
                        hitch_valid_schemas.add(schema)
                        metric_commands['hitches'].append(item['command'])
                        binding_proofs['hitches'].append({
                            'instrument':key, 'schema':item['schema'],
                            'columns':[cols[i] for i in dict.fromkeys(pcols+dcols)],
                            'sample_count':len(rows),'export_command':item['command']})
                        found_events=[]
                        for row in rows:
                            if not any(belongs(row[i],pid) for i in pcols): continue
                            duration=seconds(row[dcols[0]],cols[dcols[0]])
                            if duration is not None and duration>0:
                                found_events.append({'duration_seconds':duration,'schema':schema,'xml':item['xml']})
                        hitch_events_by_schema.setdefault(schema,[]).extend(found_events)
        units={'rss':'bytes','cpu':'percent','memory':'bytes','energy':'joules',
               'energy_impact':'relative-index'}
        for target in reading:
            metric=summarize(reading[target],units[target]) if reading[target] else missing(
                 'No verified process-attributed '+target+' numeric samples in exported tables', metric_commands[target] or [
                     'xcrun xctrace export --input <trace> --toc (no matching table)'])
            if metric['status']=='MEASURED': metric['sources']=metric_commands[target]
            status['metrics'][target]=metric
        # Energy has two distinct units: Joules or a relative Energy Impact index.
        if status['metrics']['energy']['status']!='MEASURED' and status['metrics']['energy_impact']['status']=='MEASURED':
            status['metrics']['energy']=dict(status['metrics']['energy_impact'])
            status['metrics']['energy']['note']='Relative Energy Impact index, NOT joules'
            binding_proofs['energy']=list(binding_proofs['energy_impact'])
        # The successor template records, but carries no energy metric. Declare that
        # absence by code instead of relabelling Power Impact as energy; the reason
        # names the toolchain gap and validate re-checks both halves of it.
        if (status['metrics']['energy']['status']!='MEASURED'
                and 'Energy Log' not in available
                and status['templates_used']['energy']['template'] in available
                and status['templates_used']['energy']['template']!='Energy Log'):
            status['declared_absences'].append({
                'dimension':'energy', 'code':ENERGY_GAP_CODE, 'reason':ENERGY_GAP_REASON,
                'evidence':{'energy_log_in_templates':False,
                            'successor_template':status['templates_used']['energy']['template'],
                            'successor_schema_carries_energy':False,
                            'note':'Power Profiler exports per-process Power Impact indices, not Joules'}})
            status['metrics']['energy']=missing(ENERGY_GAP_REASON,
                metric_commands['energy'] or [
                    'xcrun xctrace export --input <energy.trace> --toc (no energy-labelled table)'])
            status['metrics']['energy']['declared_absence']=ENERGY_GAP_CODE
        if thermal_rows:
            status['metrics']['thermal']={'status':'MEASURED','scope':'device',
                  'observed_states':thermal_rows,'peak':None,
                  'note':'Categorical iPhone device thermal states; no invented Celsius or process temperature',
                  'commands_attempted':metric_commands['thermal']}
        else:
            status['metrics']['thermal']=missing('No exported device thermal-state rows; no Celsius/process temperature derivation',
                                                 metric_commands['thermal'] or ['xcrun xctrace export --input <energy.trace> --toc'])
        # Render vs lifetime can describe the SAME hitch; never add their counts.
        # Prefer process-attributed render hitches when it has a true hitch duration,
        # otherwise a single process-attributed event schema. Global summary is not per app.
        primary=next((n for n in sorted(hitch_valid_schemas) if 'render' in n),
                     next(iter(sorted(hitch_valid_schemas)),None))
        if primary is not None:
            events=hitch_events_by_schema.get(primary,[])
            status['metrics']['hitches']={'status':'MEASURED','count':len(events),
                'event_schema':primary,'scope':'one process-attributed hitch event schema; not summed across schemas',
                'other_schema_counts':{k:len(v) for k,v in hitch_events_by_schema.items() if k!=primary},
                'max_duration_seconds':max((v['duration_seconds'] for v in events),default=None),
                'commands_attempted':metric_commands['hitches']}
        else:
            status['metrics']['hitches']=missing(
                'No per-process event table with an explicitly labeled hitch duration; processless hitches-summary cannot establish app count',
                metric_commands['hitches'] or ['xcrun xctrace export --input <hitches.trace> --toc'])
        status['metrics']['scroll_time']=measured_swipes(pathlib.Path(status['run_directory'])/'B03-A.log')
        if status['metrics']['scroll_time']['status']=='MEASURED':
            binding_proofs['scroll_time'].append({
                'instrument':'frozen B03 XCUITest log','schema':'B03-A.log step records',
                'columns':[{'name':'t', 'unit':'seconds'},
                           {'name':'Swipe up', 'type':'XCTest action'}],
                'sample_count':status['metrics']['scroll_time']['swipe_steps'],
                'export_command':status['metrics']['scroll_time']['command']})
        # Compare exported trace-relative time spans with observed swipe-window
        # duration. Short recordings are PARTIAL even when export and exit succeeded.
        duration=status['metrics']['scroll_time'].get('elapsed_seconds_first_to_last_swipe')
        status['trace_time_spans_seconds']=table_time_spans
        for key,spec in status['recordings'].items():
            if validate:
                # An intentional short probe must never satisfy full B03 coverage.
                spec['coverage']='VALIDATION_WINDOW_ONLY_NOT_GATE'
                continue
            relevant=[v for k,v in table_time_spans.items() if any(
                k==t.get('schema') for t in spec.get('tables',[]) if t.get('status')=='EXPORTED')]
            if spec['status']!='RECORDED': continue
            if not relevant or duration is None:
                spec['coverage']='UNKNOWN: no time-series span or measured swipe duration'
                errors.append(key+': complete trace coverage not verifiable')
                continue
            span=max(v[1]-v[0] for v in relevant)
            spec['observed_span_seconds']=span
            if span+15 < duration:
                spec['status']='PARTIAL'
                spec['reason']=f'Trace time span {span:.2f}s shorter than observed swipe window {duration:.2f}s'
                errors.append(key+': '+spec['reason'])
            else:
                spec['coverage']='OBSERVED_SPAN_COVERS_SWIPE_DURATION (clock alignment not proven)'
        status['metrics']['peaks_and_trends']={k:{'peak':v.get('peak'), 'trend':v.get('post_warmup_trend',missing('Not available'))}
                     for k,v in status['metrics'].items() if k in ('rss','cpu','memory','energy')}
        # The short validation proves actual column bindings, never a gate result.
        # A measured zero hitches is allowed only with process and duration columns.
        status['metric_bindings']=binding_proofs
        if validate:
            required=('rss','cpu','memory','energy','thermal','hitches','scroll_time')
            declared_verified=[]
            for name in required:
                metric=status['metrics'][name]
                proofs=binding_proofs[name]
                bound=metric['status']=='MEASURED' and bool(proofs)
                declaration=next((d for d in status['declared_absences']
                                  if d['dimension']==name
                                  and d['code']==metric.get('declared_absence')),None)
                # Exactly one documented absence exists: the Energy Log template gap.
                # It is accepted only while the installed toolchain still shows Energy
                # Log missing AND the named successor template present. Any other
                # unbound dimension stays a hard failure.
                if (not bound and declaration is not None
                        and declaration['code']==ENERGY_GAP_CODE
                        and declaration['evidence']['energy_log_in_templates'] is False
                        and 'Energy Log' not in available
                        and declaration['evidence']['successor_template'] in available):
                    declared_verified.append({'dimension':name, 'code':declaration['code'],
                                              'reason':declaration['reason'],
                                              'evidence':declaration['evidence']})
                    print(f'VALIDATE {name}: DECLARED_ABSENT code={declaration["code"]}'
                          f' successor_template={declaration["evidence"]["successor_template"]}'
                          f' metric_status={metric["status"]}',flush=True)
                    print('  reason='+declaration['reason'],flush=True)
                    continue
                if not bound:
                    errors.append(f'UNBOUND {name}: '+metric.get('reason','no verifiable source columns'))
                print(f'VALIDATE {name}: '+('BOUND' if bound else 'UNBOUND')+
                      f' metric_status={metric["status"]}',flush=True)
                if proofs:
                    for proof in proofs:
                        names=[(c.get('mnemonic') or c.get('name') or '<unnamed>') for c in proof['columns']]
                        print('  schema='+proof['schema']+' columns='+json.dumps(names)+
                              ' samples='+str(proof['sample_count']),flush=True)
                else:
                    candidates=[v for v in status['exported_schema_columns']
                                if v['instrument']==({'rss':'resources','cpu':'resources',
                                    'memory':'resources','energy':'energy',
                                    'thermal':'energy','hitches':'hitches'}.get(name))]
                    print('  No bound columns. Actual exported schemas/columns: '+
                          json.dumps([{'schema':v['schema'],
                            'columns':[c['mnemonic'] or c['name'] for c in v['columns']]}
                            for v in candidates]),flush=True)
            for key,spec in status['recordings'].items():
                if spec['status']!='RECORDED' or spec.get('reason'):
                    errors.append(key+': invalid validation recording: '+
                                  spec['status']+' '+str(spec.get('reason')))
                elif not spec.get('tables'):
                    errors.append(key+': zero tables exported from the recorded trace')
            status['is_gate_evidence']=False
            status['declared_absences_verified']=declared_verified
            if errors:
                status['validation_verdict']='BINDINGS_FAILED_NOT_GATE'
                status['status']='VALIDATION_FAILED_NOT_GATE'
            elif declared_verified:
                # Declared incompleteness is not a verified binding and never gate proof.
                status['validation_verdict']='BINDINGS_INCOMPLETE_DECLARED'
                status['status']='VALIDATION_INCOMPLETE_DECLARED'
            else:
                status['validation_verdict']='BINDINGS_VERIFIED_NOT_GATE'
                status['status']='VALIDATION_ONLY_NOT_GATE'
        else:
            # Certification retains the original gate-evidence completeness checks.
            for key,spec in status['recordings'].items():
                if spec['reason'] is None and spec['status']!='RECORDED':
                    errors.append(f'{key}: trace status {spec["status"]} ({spec.get("reason")})')
                if spec['reason'] is not None and spec.get('command'):
                    errors.append(f'{key}: {spec["reason"]}')
            if not status['recordings']['hitches'].get('tables'):
                errors.append('Animation Hitches recording has no exportable tables')
            for name in ('rss','cpu','memory','energy','thermal','hitches','scroll_time'):
                if status['metrics'][name]['status']!='MEASURED':
                    code=status['metrics'][name].get('declared_absence')
                    # A declared absence stays a certification failure: only an
                    # actual measurement can make B06 gate evidence.
                    errors.append(name+': '+(code+' — ' if code else '')+
                                  status['metrics'][name].get('reason','not measured'))
            status['status']='EVIDENCE_ONLY_NOT_PASS' if not errors else 'INCOMPLETE'
            status['is_gate_evidence']=not errors
    except BaseException as exc:
        errors.append(type(exc).__name__+': '+str(exc))
        status['status']='INCOMPLETE'
    finally:
        if runner is not None and runner.poll() is None:
            # Even a wedged frozen driver must not convert a short probe into
            # an unbounded 30-minute run. Only interrupt the spawned process group.
            try:
                os.killpg(runner.pid, signal.SIGINT)
            except ProcessLookupError:
                pass  # the process group finished between poll and signal
            try:
                runner.wait(timeout=30 if validate else 120)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(runner.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    runner.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    os.killpg(runner.pid, signal.SIGKILL)
                    runner.wait(timeout=15)
                errors.append('B03 driver required forced termination')
        for key,proc in recordings.items():
            if proc.poll() is None:
                os.killpg(proc.pid,signal.SIGINT)
                try: proc.wait(timeout=120)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid,signal.SIGTERM)
                    proc.wait(timeout=30)
            if key in streams and not streams[key].closed: streams[key].close()
        if out is not None:
            status['ended_at']=now()
            write_json(out/'summary.json',status)
            if (temp/'journey.log').exists():
                shutil.copy(temp/'journey.log',out/'journey.log')
            print('Package:',out)
        else:
            print('B06 did not create a package; see error below',file=sys.stderr)
        print('Re-run:',replay)
        if validate: print('SCHEMA VALIDATION ONLY — NO B03/B06 GATE EVIDENCE',flush=True)
        if errors: print('INCOMPLETE: '+'; '.join(errors),file=sys.stderr)
if status['status'] in ('INCOMPLETE','VALIDATION_FAILED_NOT_GATE'): sys.exit(1)
PY
