import type { NativeObservation } from './native-report.ts';
type Row=Record<string,unknown>;
const row=(value:unknown):Row=>value&&typeof value==='object'&&!Array.isArray(value)?value as Row:{};
export function nodeAssertionReport(observation:NativeObservation){
 const errors:string[]=[],suites=new Map<string,{name:string;assertionResults:{title:string;status:string;duration:number|null;failureMessages:string[]}[]}>();
 let summaries=0,summary:Row={},failedSuites=0,pendingSuites=0;
 if(observation.format!=='node')errors.push('native_format_mismatch');
 for(const line of observation.stdout.split('\n').filter(Boolean)){
  let event:Row;try{event=row(JSON.parse(line));}catch{errors.push('native_event_stream_incomplete');continue;}
  const data=row(event.data),details=row(data.details);
  if(event.type==='test:summary'&&data.file===undefined){summaries++;summary=data;}
  if((event.type==='test:pass'||event.type==='test:fail')&&details.type==='suite'){
   if(event.type==='test:fail')failedSuites++;if(data.skip||data.todo)pendingSuites++;
  }
  if((event.type==='test:pass'||event.type==='test:fail')&&details.type==='test'){
   if(typeof data.file!=='string'||typeof data.name!=='string'||!data.name||!data.file){errors.push('native_assertion_identity_unavailable');continue;}
   const suite=suites.get(data.file)??{name:data.file,assertionResults:[]};
   const title=typeof data.fullName==='string'?data.fullName:data.name;
   if(suite.assertionResults.some(value=>value.title===title))errors.push('native_assertion_identity_duplicate');
   const duration=typeof details.duration_ms==='number'&&Number.isFinite(details.duration_ms)&&details.duration_ms>=0?details.duration_ms:null;
   if(duration===null)errors.push('test_timing_unavailable');
   const status=data.skip?'skipped':data.todo?'todo':event.type==='test:pass'?'passed':'failed';
   suite.assertionResults.push({title,status,duration,failureMessages:status==='failed'?['Native Node test failed; original events retained.']:[]});suites.set(data.file,suite);
  }
 }
 const counts=row(summary.counts),count=(name:string)=>{const value=counts[name];if(typeof value!=='number'||!Number.isSafeInteger(value)||value<0){errors.push('native_terminal_counts_unavailable');return 0;}return value;};
 const numTotalTests=count('tests'),numPassedTests=count('passed'),numFailedTests=count('failed')+count('cancelled'),numPendingTests=count('skipped'),numTodoTests=count('todo');
 const values=[...suites.values()].flatMap(suite=>suite.assertionResults);
 if(summaries!==1)errors.push('native_terminal_summary_missing_or_duplicate');
 if(!values.length||!numTotalTests)errors.push('native_assertions_missing');
 if(values.length!==numTotalTests||numTotalTests!==numPassedTests+numFailedTests+numPendingTests+numTodoTests
  ||values.filter(value=>value.status==='passed').length!==numPassedTests||values.filter(value=>value.status==='failed').length!==numFailedTests
  ||values.filter(value=>value.status==='skipped').length!==numPendingTests||values.filter(value=>value.status==='todo').length!==numTodoTests)errors.push('native_assertion_count_conflict');
 if(observation.exitCode!==0||observation.signal!==null||summary.success!==true)errors.push('native_process_failed_or_interrupted');
 return {success:errors.length===0&&numTotalTests>0&&numPassedTests===numTotalTests,numTotalTests,numPassedTests,numFailedTests,numPendingTests,numTodoTests,
  numFailedTestSuites:failedSuites,numPendingTestSuites:pendingSuites,testResults:[...suites.values()],errors:[...new Set(errors)],raw:structuredClone(observation)};
}
