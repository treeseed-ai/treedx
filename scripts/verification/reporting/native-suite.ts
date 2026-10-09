import { spawn } from 'node:child_process';
import { nativeAssertionReport } from './native-report.ts';
type NativeReport=ReturnType<typeof nativeAssertionReport>;
type Execution={command:string[];cwd:string;stdout:string;stderr:string;exitCode:number|null;signal:string|null};
export function combineNativeReports(reports:NativeReport[],execution:Execution){
 const errors:string[]=[];
 if(!reports.length)errors.push('native_reports_missing');
 if(execution.exitCode!==0||execution.signal!==null)errors.push('native_owner_process_failed_or_interrupted');
 for(const report of reports){const values=report.testResults.flatMap(suite=>suite.assertionResults);
  if(report.success!==true||!Number.isSafeInteger(report.numTotalTests)||report.numTotalTests<1||report.numPassedTests!==report.numTotalTests
   ||report.numFailedTests!==0||report.numPendingTests!==0||report.numTodoTests!==0||report.numFailedTestSuites!==0||report.numPendingTestSuites!==0
   ||values.length!==report.numTotalTests||values.some(value=>value.status!=='passed'||!value.title||typeof value.duration!=='number'||!Number.isFinite(value.duration)||value.duration<0))errors.push('native_owner_assertions_incomplete');
 }
 const total=(key:'numTotalTests'|'numPassedTests'|'numFailedTests'|'numPendingTests'|'numTodoTests'|'numFailedTestSuites'|'numPendingTestSuites')=>reports.reduce((sum,report)=>sum+report[key],0);
 const testResults=reports.flatMap((report,index)=>report.testResults.map(suite=>({...structuredClone(suite),name:`${index+1}: ${report.raw.cwd} ${JSON.stringify(report.raw.command)} / ${suite.name}`})));
 return {success:errors.length===0,numTotalTests:total('numTotalTests'),numPassedTests:total('numPassedTests'),numFailedTests:total('numFailedTests'),numPendingTests:total('numPendingTests'),numTodoTests:total('numTodoTests'),numFailedTestSuites:total('numFailedTestSuites'),numPendingTestSuites:total('numPendingTestSuites'),testResults,errors:[...new Set(errors)],nativeReports:structuredClone(reports),execution:structuredClone(execution)};
}

/** Original scripts keep execution ownership; fd 3 carries only their assertion reports. */
export async function collectNativeSuite(command:string[],cwd:string,options:{signal?:AbortSignal;onStdout?:(chunk:string)=>void}={}){
 const child=spawn(command[0]!,command.slice(1),{cwd,detached:true,stdio:['ignore','pipe','pipe','pipe'],env:{...process.env,TREESEED_NATIVE_REPORT_FD:'3'}});
 if(!child.stdout||!child.stderr)throw new Error('Native output channels are unavailable.');
 const stdout:Buffer[]=[],stderr:Buffer[]=[],records:Buffer[]=[];
 child.stdout.on('data',(bytes:Buffer)=>{stdout.push(bytes);process.stderr.write(bytes);options.onStdout?.(bytes.toString('utf8'));});
 child.stderr.on('data',(bytes:Buffer)=>{stderr.push(bytes);process.stderr.write(bytes);});
 const channel=child.stdio[3];if(!channel||!('on' in channel))throw new Error('Native report channel is unavailable.');
 channel.on('data',(bytes:Buffer)=>records.push(bytes));
 const startedAt=new Date().toISOString();
 const stop=()=>{if(child.pid){try{process.kill(-child.pid,'SIGTERM');}catch(error){if((error as NodeJS.ErrnoException).code!=='ESRCH')throw error;}}};
 const result=await new Promise<{exitCode:number|null;signal:NodeJS.Signals|null}>((resolve,reject)=>{child.once('error',reject);child.once('close',(exitCode,signal)=>resolve({exitCode,signal}));options.signal?.addEventListener('abort',stop,{once:true});if(options.signal?.aborted)stop();}).finally(()=>options.signal?.removeEventListener('abort',stop));
 const reports:NativeReport[]=[];const stream=Buffer.concat(records).toString('utf8');let malformed=Boolean(stream)&&!stream.endsWith('\n');
 for(const line of stream.split('\n').filter(Boolean)){
  try{const report:unknown=JSON.parse(line);if(!report||typeof report!=='object'||!('raw' in report))throw new Error('Missing native observation.');reports.push(nativeAssertionReport((report as NativeReport).raw));}catch{malformed=true;}
 }
 const report=combineNativeReports(reports,{command:[...command],cwd,stdout:Buffer.concat(stdout).toString('utf8'),stderr:Buffer.concat(stderr).toString('utf8'),...result});
 if(malformed){report.success=false;report.errors.push('native_report_channel_incomplete');}
 return {...report,startedAt,completedAt:new Date().toISOString()};
}
