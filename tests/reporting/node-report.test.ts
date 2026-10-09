import assert from 'node:assert/strict';
import test from 'node:test';
import { nodeAssertionReport } from '../../scripts/verification/reporting/node-report.ts';
const events=[{type:'test:pass',data:{name:'exact boundary',file:'/held-owner/tests/boundary.test.ts',line:3,column:1,nesting:0,details:{type:'test',duration_ms:123.456}}},
 {type:'test:summary',data:{success:true,counts:{tests:1,passed:1,failed:0,cancelled:0,skipped:0,todo:0,suites:0}}}];
const native={format:'node' as const,command:['node','--test','tests/boundary.test.ts'],cwd:'/held-owner',stdout:events.map(value=>JSON.stringify(value)).join('\n')+'\n',stderr:'',exitCode:0,signal:null,trace:''};
test('strict native Node reporting preserves terminal event identity status and measured timing',()=>{
 const report=nodeAssertionReport(native);assert.equal(report.success,true);assert.equal(report.numPassedTests,1);assert.equal(report.testResults[0]!.name,'/held-owner/tests/boundary.test.ts');assert.deepEqual(report.testResults[0]!.assertionResults[0],{title:'exact boundary',status:'passed',duration:123.456,failureMessages:[]});assert.deepEqual(report.raw,native);
});
test('strict native Node reporting rejects missing interrupted duplicated malformed skipped todo filtered or unmeasured native events',()=>{
 for(const changed of [events.slice(0,1),[events[0],events[0],events[1]],[{...events[0],data:{...events[0]!.data,details:{type:'test'}}},events[1]],
  [{...events[0],data:{...events[0]!.data,skip:true}},events[1]],[{...events[0],data:{...events[0]!.data,todo:true}},events[1]],
  [events[0],{type:'test:summary',data:{success:true,counts:{tests:2,passed:2,failed:0,cancelled:0,skipped:0,todo:0,suites:0}}}],
 ]){const supplied={...native,stdout:changed.map(value=>JSON.stringify(value)).join('\n')+'\n'},report=nodeAssertionReport(supplied);assert.equal(report.success,false);assert.deepEqual(report.raw,supplied);}
 for(const supplied of [{...native,stdout:native.stdout.slice(0,-4)},{...native,exitCode:null,signal:'SIGTERM'}]){const report=nodeAssertionReport(supplied);assert.equal(report.success,false);assert.deepEqual(report.raw,supplied);}
});
