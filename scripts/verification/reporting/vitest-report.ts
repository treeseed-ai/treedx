import type { NativeObservation } from './native-report.ts';
type Row=Record<string,unknown>;
const row=(value:unknown):Row=>value&&typeof value==='object'&&!Array.isArray(value)?value as Row:{};
export function vitestAssertionReport(observation:NativeObservation){
 const errors:string[]=[],suites:{name:string;assertionResults:{title:string;status:string;duration:number|null;failureMessages:string[]}[]}[]=[];
 let report:Row={};try{report=row(JSON.parse(observation.report??''));}catch{errors.push('native_report_file_incomplete');}
 if(observation.format!=='vitest')errors.push('native_format_mismatch');
 const count=(name:string)=>{const value=report[name];if(typeof value!=='number'||!Number.isSafeInteger(value)||value<0){errors.push('native_terminal_counts_unavailable');return 0;}return value;};
 const numTotalTests=count('numTotalTests'),numPassedTests=count('numPassedTests'),numFailedTests=count('numFailedTests'),numPendingTests=count('numPendingTests'),numTodoTests=count('numTodoTests'),numFailedTestSuites=count('numFailedTestSuites'),numPendingTestSuites=count('numPendingTestSuites');
 if(!Array.isArray(report.testResults))errors.push('native_assertions_missing');
 else for(const value of report.testResults){
  const file=row(value),suite:{name:string;assertionResults:typeof suites[number]['assertionResults']}={name:typeof file.name==='string'?file.name:'',assertionResults:[]};
  if(!suite.name||suites.some(value=>value.name===suite.name))errors.push('native_target_identity_unavailable_or_duplicate');
  if(!Array.isArray(file.assertionResults)){errors.push('native_assertions_missing');continue;}
  for(const value of file.assertionResults){const assertion=row(value),title=typeof assertion.fullName==='string'?assertion.fullName:assertion.title;
   if(typeof title!=='string'||!title||typeof assertion.status!=='string'){errors.push('native_assertion_identity_unavailable');continue;}
   if(suite.assertionResults.some(value=>value.title===title))errors.push('native_assertion_identity_duplicate');
   const duration=typeof assertion.duration==='number'&&Number.isFinite(assertion.duration)&&assertion.duration>=0?assertion.duration:null;
   if(duration===null)errors.push('test_timing_unavailable');
   suite.assertionResults.push({title,status:assertion.status,duration,failureMessages:assertion.status==='failed'?['Native Vitest assertion failed; original report retained.']:[]});
  }suites.push(suite);
 }
 const values=suites.flatMap(suite=>suite.assertionResults);
 if(!values.length||!numTotalTests)errors.push('native_assertions_missing');
 if(values.length!==numTotalTests||numTotalTests!==numPassedTests+numFailedTests+numPendingTests+numTodoTests
  ||values.filter(value=>value.status==='passed').length!==numPassedTests||values.filter(value=>value.status==='failed').length!==numFailedTests
  ||values.filter(value=>['skipped','pending'].includes(value.status)).length!==numPendingTests||values.filter(value=>value.status==='todo').length!==numTodoTests)errors.push('native_assertion_count_conflict');
 if(observation.exitCode!==0||observation.signal!==null||report.success!==true)errors.push('native_process_failed_or_interrupted');
 return {success:errors.length===0&&numTotalTests>0&&numPassedTests===numTotalTests&&!numFailedTestSuites&&!numPendingTestSuites,numTotalTests,numPassedTests,numFailedTests,numPendingTests,numTodoTests,numFailedTestSuites,numPendingTestSuites,testResults:suites,errors:[...new Set(errors)],raw:structuredClone(observation)};
}
