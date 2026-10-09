import { writeSync } from 'node:fs';
import { collectNativeCommand } from './native-command.ts';
import { nativeAssertionReport, type NativeObservation } from './native-report.ts';
import { collectNativeSuite } from './native-suite.ts';

const [format,separator,...args]=process.argv.slice(2);
if(separator!=='--'||!args.length||!['rust','exunit','pytest','node','vitest','suite'].includes(format??''))throw new Error('An explicit native report format and original command are required.');
if(format==='suite'){
 const controller=new AbortController(),stop=()=>controller.abort();process.once('SIGTERM',stop);process.once('SIGINT',stop);
 try{const report=await collectNativeSuite(args,process.cwd(),{signal:controller.signal});process.stdout.write(JSON.stringify(report)+'\n');if(!report.success)process.exitCode=1;}finally{process.removeListener('SIGTERM',stop);process.removeListener('SIGINT',stop);}
}else{
 const command=format==='rust'?[...args,'--','--test-threads=1','--color','never']:format==='exunit'?[...args,'--trace','--color']:format==='pytest'?[...args,'-vv','--color=no','--durations=0','--durations-min=0']:args;
 const controller=new AbortController(),stop=()=>controller.abort();process.once('SIGTERM',stop);process.once('SIGINT',stop);
 try{
  const native=await collectNativeCommand(command,process.cwd(),{format:format as NativeObservation['format'],signal:controller.signal,onStdout:bytes=>process.stdout.write(bytes),onStderr:bytes=>process.stderr.write(bytes)});
  const report=nativeAssertionReport(native);
  if(process.env.TREESEED_NATIVE_REPORT_FD==='3')writeSync(3,JSON.stringify(report)+'\n');
  if(!report.success){process.stderr.write(JSON.stringify({command:native.command,errors:report.errors})+'\n');process.exitCode=1;}
 }finally{process.removeListener('SIGTERM',stop);process.removeListener('SIGINT',stop);}
}
