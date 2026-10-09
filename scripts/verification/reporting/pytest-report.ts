import type { NativeObservation } from './native-report.ts';

/** Native verbose identities and --durations=0 call observations must agree exactly. */
export function pytestAssertionReport(observation:NativeObservation){
 const errors:string[]=[],assertionResults:{title:string;status:'passed'|'failed'|'pending';duration:number|null;failureMessages:string[]}[]=[];
 if(observation.format!=='pytest')errors.push('native_format_mismatch');
 const source=observation.stdout,identities=[...source.matchAll(/^(.+::.+) (PASSED|FAILED|ERROR|SKIPPED|XFAIL|XPASS)(?: \([^\n]*\))?\s+\[\s*\d+%\]$/gmu)];
 const durations=new Map<string,number>();
 for(const match of source.matchAll(/^(\d+(?:\.\d+)?)s call\s+(.+)$/gmu)){
  if(durations.has(match[2]!))errors.push('native_assertion_timing_duplicate');durations.set(match[2]!,Number(match[1])*1000);
 }
 for(const match of identities){
  const title=match[1]!,nativeStatus=match[2]!,duration=durations.get(title)??null;
  const status=nativeStatus==='PASSED'?'passed':['SKIPPED','XFAIL'].includes(nativeStatus)?'pending':'failed';
  if(assertionResults.some(value=>value.title===title))errors.push('native_assertion_identity_duplicate');
  if(duration===null||!Number.isFinite(duration)||duration<0)errors.push('test_timing_unavailable');
  assertionResults.push({title,status,duration,failureMessages:status==='failed'?[`Native pytest ${nativeStatus}; original output retained.`]:[]});
 }
 const summaries=[...source.matchAll(/^=+ (.+) in (\d+(?:\.\d+)?)s =+$/gmu)],collections=[...source.matchAll(/collected (\d+) items?(?:\n|$)/gu)];
 if(summaries.length!==1||collections.length!==1)errors.push('native_terminal_summary_missing_or_duplicate');
 const counts=new Map<string,number>();
 for(const term of (summaries[0]?.[1]??'').split(', ')){
  const match=/^(\d+) (passed|failed|error|errors|skipped|xfailed|xpassed|deselected|warning|warnings)$/u.exec(term);
  if(!match){errors.push('native_terminal_status_unavailable');continue;}
  const key=match[2]!.replace(/^(errors|warnings)$/u,value=>value.slice(0,-1));if(counts.has(key))errors.push('native_terminal_status_duplicate');counts.set(key,Number(match[1]));
 }
 const numPassedTests=counts.get('passed')??0,numFailedTests=(counts.get('failed')??0)+(counts.get('error')??0)+(counts.get('xpassed')??0),
  numPendingTests=(counts.get('skipped')??0)+(counts.get('xfailed')??0),numTotalTests=Number(collections[0]?.[1]??0);
 if(!numTotalTests||!identities.length)errors.push('native_assertions_missing');
 if(numTotalTests!==numPassedTests+numFailedTests+numPendingTests||assertionResults.length!==numTotalTests
  ||assertionResults.filter(value=>value.status==='passed').length!==numPassedTests||assertionResults.filter(value=>value.status==='failed').length!==numFailedTests
  ||assertionResults.filter(value=>value.status==='pending').length!==numPendingTests)errors.push('native_assertion_count_conflict');
 if([...durations.keys()].some(title=>!assertionResults.some(value=>value.title===title)))errors.push('native_assertion_timing_identity_conflict');
 if(counts.has('deselected')||/\b(?:deselected|selected)\b|Interrupted:|KeyboardInterrupt/u.test(source))errors.push('native_filtered_or_interrupted');
 if(observation.exitCode!==0||observation.signal!==null)errors.push('native_process_failed_or_interrupted');
 const testResults=[{name:observation.cwd,assertionResults}];
 return {success:errors.length===0&&numTotalTests>0&&numPassedTests===numTotalTests,numTotalTests,numPassedTests,numFailedTests,numPendingTests,numTodoTests:0,
  numFailedTestSuites:numFailedTests>0?1:0,numPendingTestSuites:numPendingTests>0?1:0,testResults,errors:[...new Set(errors)],raw:structuredClone(observation)};
}
