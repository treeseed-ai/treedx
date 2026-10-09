import { vitestAssertionReport } from './vitest-report.ts';
import { nodeAssertionReport } from './node-report.ts';
import { pytestAssertionReport } from './pytest-report.ts';
import { exUnitAssertionReport } from './exunit-report.ts';
export interface NativeObservation {
 format: 'rust' | 'exunit' | 'pytest' | 'node' | 'vitest'; command: string[]; cwd: string; stdout: string; stderr: string;
 exitCode: number | null; signal: string | null; trace: string; report?:string;
}
interface Assertion { title: string; status: 'passed' | 'failed' | 'pending'; duration: number | null; failureMessages: string[] }
interface NativeSuite {
 name: string; assertionResults: Assertion[]; expected: number; terminal: boolean;
 passed: number; failed: number; ignored: number; measured: number; filtered: number;
}
interface Write { bytes: Buffer; time: bigint }

/** Decode strace's native C byte strings; an incomplete write is never timing evidence. */
function cBytes(source: string): Buffer {
 const bytes: number[] = [];
 for (let index=0;index<source.length;index++) {
  const char=source[index]!;
  if(char!=='\\') { bytes.push(...Buffer.from(char));continue; }
  const next=source[++index];
  const escapes:Record<string,number>={'n':10,'r':13,'t':9,'b':8,'f':12,'v':11,'a':7,'\\':92,'"':34};
  if(next!==undefined&&Object.hasOwn(escapes,next)){bytes.push(escapes[next]!);continue;}
  const octal=/^[0-7]{1,3}/u.exec(source.slice(index));
  if(octal){bytes.push(Number.parseInt(octal[0],8));index+=octal[0].length-1;continue;}
  const hex=next==='x'?/^[a-fA-F0-9]{2}/u.exec(source.slice(index+1)):null;
  if(hex){bytes.push(Number.parseInt(hex[0],16));index+=2;continue;}
  throw new Error('native_trace_escape_unavailable');
 }
 return Buffer.from(bytes);
}

function tracedWrites(trace: string): Map<string,Write[]> {
 const processes=new Map<string,Write[]>();
 for(const line of trace.split('\n')){
  if(!/\bwrite\(1,/u.test(line))continue;
  const match=/^(\d+)\s+(\d+)\.(\d{6})\s+write\(1, "((?:[^"\\]|\\.)*)", (\d+)\)\s+= (\d+)$/u.exec(line.trim());
  if(!match)throw new Error('native_trace_write_incomplete');
  const bytes=cBytes(match[4]!);
  if(bytes.length!==Number(match[5])||bytes.length!==Number(match[6]))throw new Error('native_trace_write_incomplete');
  const writes=processes.get(match[1]!)??[];
  const time=BigInt(match[2]!)*1_000_000n+BigInt(match[3]!);
  if(writes.length&&time<writes.at(-1)!.time)throw new Error('native_trace_clock_reversed');
  writes.push({bytes,time});processes.set(match[1]!,writes);
 }
 return processes;
}

function observedDuration(processes: Map<string,Write[]>, nativeName: string, nativeStatus: string): number | null {
 const prefix=Buffer.from(`test ${nativeName} ... `), full=Buffer.from(`test ${nativeName} ... ${nativeStatus}\n`);
 const observations:number[]=[];
 for(const writes of processes.values()){
  const stream=Buffer.concat(writes.map(write=>write.bytes));
  if(!/^running \d+ tests?\n/mu.test(stream.toString('utf8')))continue;
  const start=stream.indexOf(full);
  if(start<0)continue;
  if(stream.indexOf(full,start+1)>=0)return null;
  let offset=0,begin=-1,end=-1;
  for(const [index,write] of writes.entries()){
   offset+=write.bytes.length;
   if(begin<0&&offset>=start+prefix.length)begin=index;
   if(end<0&&offset>=start+full.length)end=index;
  }
  // Native pretty formatting flushes the prefix before executing the test.
  // One combined observed write cannot establish a test execution interval.
  if(begin<0||end<=begin)continue;
  const duration=Number(writes[end]!.time-writes[begin]!.time)/1000;
  if(Number.isFinite(duration)&&duration>=0)observations.push(duration);
 }
 return observations.length===1?observations[0]!:null;
}

/** Convert original native observations to the existing strict assertion report. */
export function nativeAssertionReport(observation: NativeObservation) {
 if(observation.format==='vitest')return vitestAssertionReport(observation);
 if(observation.format==='node')return nodeAssertionReport(observation);
 if(observation.format==='pytest')return pytestAssertionReport(observation);
 if(observation.format==='exunit')return exUnitAssertionReport(observation);
 const errors:string[]=[],suites:NativeSuite[]=[];
 const headers=[...observation.stderr.matchAll(/^\s*(Running [^\n]+|Doc-tests [^\n]+)$/gmu)].map(match=>match[1]!);
 let processes=new Map<string,Write[]>();
 try{processes=tracedWrites(observation.trace);}catch(error){errors.push(error instanceof Error?error.message:'native_trace_unavailable');}
 const streams=[...processes.values()].filter(writes=>/^running \d+ tests?\n/mu.test(Buffer.concat(writes.map(write=>write.bytes)).toString('utf8')))
  .sort((left,right)=>left[0]!.time<right[0]!.time?-1:left[0]!.time>right[0]!.time?1:0);
 if(!Buffer.concat(streams.flatMap(writes=>writes.map(write=>write.bytes))).equals(Buffer.from(observation.stdout)))errors.push('native_trace_stream_conflict');
 let active:NativeSuite|undefined;
 for(const line of observation.stdout.split('\n')){
  const start=/^running (\d+) tests?$/u.exec(line);
  if(start){
   if(active&&!active.terminal)errors.push('native_terminal_summary_missing');
   const header=headers[suites.length];
   if(!header)errors.push('native_target_identity_unavailable');
   active={name:header??'',assertionResults:[],expected:Number(start[1]),terminal:false,passed:0,failed:0,ignored:0,measured:0,filtered:0};
   suites.push(active);continue;
  }
  const assertion=/^test (.+) \.\.\. (ok|FAILED|ignored)(?:, .*)?$/u.exec(line);
  if(assertion){
   if(!active||active.terminal){errors.push('native_assertion_outside_suite');continue;}
   const title=assertion[1]!,status=assertion[2]!,duration=observedDuration(processes,title,status);
   if(active.assertionResults.some(value=>value.title===title))errors.push('native_assertion_identity_duplicate');
   if(duration===null)errors.push('test_timing_unavailable');
   active.assertionResults.push({title,status:status==='ok'?'passed':status==='FAILED'?'failed':'pending',duration,failureMessages:status==='FAILED'?['Native Rust assertion failed; original output retained.']:[]});
   continue;
  }
  const terminal=/^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out; finished in ([\d.]+)s$/u.exec(line);
  if(terminal){
   if(!active||active.terminal){errors.push('native_terminal_summary_duplicate');continue;}
   active.terminal=true;active.passed=Number(terminal[2]);active.failed=Number(terminal[3]);active.ignored=Number(terminal[4]);active.measured=Number(terminal[5]);active.filtered=Number(terminal[6]);
   if(!Number.isFinite(Number(terminal[7]))||Number(terminal[7])<0)errors.push('native_suite_time_unavailable');
   if((terminal[1]==='ok')!==(active.failed===0))errors.push('native_terminal_status_conflict');
   if(active.measured||active.filtered)errors.push('native_filtered_or_measured');
   const values=active.assertionResults;
   if(values.length!==active.expected||active.expected!==active.passed+active.failed+active.ignored
    ||values.filter(value=>value.status==='passed').length!==active.passed||values.filter(value=>value.status==='failed').length!==active.failed
    ||values.filter(value=>value.status==='pending').length!==active.ignored)errors.push('native_assertion_count_conflict');
  }
 }
 if(!suites.length||!suites.some(suite=>suite.expected>0))errors.push('native_assertions_missing');
 if(suites.some(suite=>!suite.terminal))errors.push('native_terminal_summary_missing');
 if(headers.length!==suites.length)errors.push('native_target_count_conflict');
 if(observation.exitCode!==0||observation.signal!==null)errors.push('native_process_failed_or_interrupted');
 const numTotalTests=suites.reduce((sum,suite)=>sum+suite.expected,0),numPassedTests=suites.reduce((sum,suite)=>sum+suite.passed,0),
  numFailedTests=suites.reduce((sum,suite)=>sum+suite.failed,0),numPendingTests=suites.reduce((sum,suite)=>sum+suite.ignored,0);
 return {success:errors.length===0&&numTotalTests>0&&numPassedTests===numTotalTests,
  numTotalTests,numPassedTests,numFailedTests,numPendingTests,numTodoTests:0,
  numFailedTestSuites:suites.filter(suite=>suite.failed>0).length,numPendingTestSuites:suites.filter(suite=>suite.ignored>0).length,
  testResults:suites.map(suite=>({name:suite.name,assertionResults:suite.assertionResults})),errors:[...new Set(errors)],raw:structuredClone(observation)};
}
