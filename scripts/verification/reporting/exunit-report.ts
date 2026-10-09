import type { NativeObservation } from './native-report.ts';
type Assertion={title:string;status:'passed'|'failed'|'pending';duration:number|null;failureMessages:string[]};

/** ExUnit's forced native color identifies each result; no exit-zero inference. */
export function exUnitAssertionReport(observation:NativeObservation){
 const errors:string[]=[],suites:{name:string;assertionResults:Assertion[]}[]=[];
 if(observation.format!=='exunit')errors.push('native_format_mismatch');
 const plain=observation.stdout.replace(/\u001b\[[0-9;]*m/gu,'');
 let active:typeof suites[number]|undefined;
 for(const line of observation.stdout.split('\n')){
  const module=/^([^\s\u001b][^\u001b\r\n]*) \[([^\]\r\n]+\.exs)\]$/u.exec(line);
  if(module){active={name:`${module[1]} [${module[2]}]`,assertionResults:[]};
   if(suites.some(suite=>suite.name===active!.name))errors.push('native_target_identity_duplicate');suites.push(active);continue;}
  const result=/\u001b\[(32|31|33)m\r  \* (.+) \((\d+(?:\.\d+)?ms|skipped|excluded)\) \[(L#\d+)\]\u001b\[0m$/u.exec(line);
  if(!result){if(/\r  \*/u.test(line))errors.push('native_assertion_status_or_time_unavailable');continue;}
  if(!active){errors.push('native_target_identity_unavailable');continue;}
  const title=`${result[2]} [${result[4]}]`,color=result[1],timing=result[3]!;
  const duration=/ms$/u.test(timing)?Number(timing.slice(0,-2)):null;
  const status=color==='32'?'passed':color==='31'?'failed':'pending';
  if(active.assertionResults.some(value=>value.title===title))errors.push('native_assertion_identity_duplicate');
  if(status!=='pending'&&(duration===null||!Number.isFinite(duration)||duration<0))errors.push('test_timing_unavailable');
  if(status==='pending')errors.push('native_skipped_or_excluded');
  if((status==='pending')!==(timing==='skipped'||timing==='excluded'))errors.push('native_assertion_status_conflict');
  active.assertionResults.push({title,status,duration,failureMessages:status==='failed'?['Native ExUnit assertion failed; original output retained.']:[]});
 }
 const summary=[...plain.matchAll(/^(?:(\d+) doctests?, )?(?:(\d+) tests?, )?(\d+) failures?(?:, (\d+) excluded)?(?:, (\d+) invalid)?(?:, (\d+) skipped)?$/gmu)];
 const times=[...plain.matchAll(/^Finished in \d+(?:\.\d+)? seconds? \([^\n]+\)$/gmu)];
 if(summary.length!==1||times.length!==1)errors.push('native_terminal_summary_missing_or_duplicate');
 if(/(?:Excluding|Including) tags:|All tests have been excluded|--max-failures|Aborting test suite/iu.test(plain))errors.push('native_filtered_or_interrupted');
 const row=summary[0],numTotalTests=row?Number(row[1]??0)+Number(row[2]??0):0,
  numFailedTests=Number(row?.[3]??0)+Number(row?.[5]??0),numPendingTests=Number(row?.[4]??0)+Number(row?.[6]??0),
  numPassedTests=numTotalTests-numFailedTests-numPendingTests;
 const values=suites.flatMap(suite=>suite.assertionResults);
 if(!values.length)errors.push('native_assertions_missing');
 if(values.length!==numTotalTests||values.filter(value=>value.status==='passed').length!==numPassedTests
  ||values.filter(value=>value.status==='failed').length!==numFailedTests||values.filter(value=>value.status==='pending').length!==numPendingTests)errors.push('native_assertion_count_conflict');
 if(observation.exitCode!==0||observation.signal!==null)errors.push('native_process_failed_or_interrupted');
 return {success:errors.length===0&&numTotalTests>0&&numPassedTests===numTotalTests,numTotalTests,numPassedTests,numFailedTests,numPendingTests,numTodoTests:0,
  numFailedTestSuites:suites.filter(suite=>suite.assertionResults.some(value=>value.status==='failed')).length,
  numPendingTestSuites:suites.filter(suite=>suite.assertionResults.some(value=>value.status==='pending')).length,
  testResults:suites,errors:[...new Set(errors)],raw:structuredClone(observation)};
}
