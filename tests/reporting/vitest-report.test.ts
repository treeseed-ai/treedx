import assert from 'node:assert/strict';
import test from 'node:test';
import { vitestAssertionReport } from '../../scripts/verification/reporting/vitest-report.ts';
const report={success:true,numTotalTests:1,numPassedTests:1,numFailedTests:0,numPendingTests:0,numTodoTests:0,numFailedTestSuites:0,numPendingTestSuites:0,testResults:[{name:'/held-owner/boundary.test.ts',assertionResults:[{title:'exact boundary',fullName:'native exact boundary',status:'passed',duration:12.3,failureMessages:[]}]}]};
const native={format:'vitest' as const,command:['npm','test'],cwd:'/held-owner',stdout:'original child stdout\n',stderr:'',exitCode:0,signal:null,trace:'',report:JSON.stringify(report)};
test('strict native Vitest reporting retains actual report-file bytes independently of native child stdout and exact assertion counts',()=>{
 const result=vitestAssertionReport(native);assert.equal(result.success,true);assert.equal(result.numTotalTests,1);assert.equal(result.testResults[0]!.assertionResults[0]!.title,'native exact boundary');assert.equal(result.testResults[0]!.assertionResults[0]!.duration,12.3);assert.deepEqual(result.raw,native);
});
test('strict native Vitest reporting rejects partial missing malformed duplicate skipped unmeasured or interrupted report files',()=>{
 for(const supplied of [{...native,report:undefined},{...native,report:'{truncated'},
  {...native,report:JSON.stringify({...report,numTotalTests:2})},
  {...native,report:JSON.stringify({...report,testResults:[report.testResults[0],report.testResults[0]]})},
  {...native,report:JSON.stringify({...report,testResults:[{name:'file',assertionResults:[{title:'native exact boundary',status:'passed'}]}]})},
  {...native,report:JSON.stringify({...report,numPendingTests:1,numPassedTests:0})},{...native,signal:'SIGTERM',exitCode:null},
 ]){const result=vitestAssertionReport(supplied);assert.equal(result.success,false);assert.deepEqual(result.raw,supplied);}
});
