import assert from 'node:assert/strict';
import test from 'node:test';
import { combineNativeReports } from '../../scripts/verification/reporting/native-suite.ts';
import { nativeAssertionReport } from '../../scripts/verification/reporting/native-report.ts';
const native={format:'node' as const,command:['node','--test','unit.test.ts'],cwd:'/held-owner',stdout:[{type:'test:pass',data:{name:'exact boundary',file:'/held-owner/unit.test.ts',details:{type:'test',duration_ms:1.23}}},{type:'test:summary',data:{success:true,counts:{tests:1,passed:1,failed:0,cancelled:0,skipped:0,todo:0}}}].map(value=>JSON.stringify(value)).join('\n')+'\n',stderr:'',exitCode:0,signal:null,trace:''};
const run={command:['bash','test-all.sh'],cwd:'/held-owner',stdout:'original owning output\n',stderr:'',exitCode:0,signal:null};
test('complete native suite collection retains exact native counts commands observations and test identities without mutation',()=>{
 const reports=[nativeAssertionReport(native),nativeAssertionReport({...native,command:['node','--test','integration.test.ts']})],before=structuredClone(reports),result=combineNativeReports(reports,run);
 assert.equal(result.success,true);assert.equal(result.numTotalTests,2);assert.equal(result.numPassedTests,2);assert.equal(result.testResults.length,2);assert.deepEqual(result.nativeReports,before);assert.deepEqual(result.execution,run);assert.deepEqual(reports,before);
});
test('complete native suite collection never certifies missing or partial reports interrupted scripts or malformed assertion totals',()=>{
 const complete=nativeAssertionReport(native);
 for(const reports of [[],[{...complete,numTotalTests:2}],[{...complete,testResults:[]}],[{...complete,success:false}],[{...complete,numPendingTests:1}]] )assert.equal(combineNativeReports(reports,run).success,false);
 for(const execution of [{...run,exitCode:1},{...run,signal:'SIGTERM',exitCode:null}]){const result=combineNativeReports([complete],execution);assert.equal(result.success,false);assert.deepEqual(result.execution,execution);}
});
