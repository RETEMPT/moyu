import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { spawn } from 'node:child_process';
import os from 'node:os';
import { createInterface } from 'node:readline';
import { resolveTypeScript } from '../resolve-typescript.mjs';

const root=path.resolve(import.meta.dirname,'../..'),ts=resolveTypeScript();
const bundledPython=path.join(os.homedir(),'.cache','codex-runtimes','codex-primary-runtime','dependencies','python','python.exe');
const python=process.env.PYTHON||(process.platform==='win32'&&fs.existsSync(bundledPython)?bundledPython:process.platform==='win32'?'python':'python3');
function resultSet(rows){let index=-1;return{goToFirstRow:()=>{index=0;return rows.length>0;},goToNextRow:()=>++index<rows.length,
  getLong:column=>rows[index][column],getDouble:column=>rows[index][column],getString:column=>rows[index][column],close(){}};}
export function fixture(t, legacy = {}){
  const child=spawn(python,['-X','utf8','-u',path.join(root,'tools/fixtures/sqlite-port.py')],{windowsHide:true,stdio:['pipe','pipe','pipe']});
  let sequence=0,fail=null;const pending=new Map();let stderr='';
  child.stderr.on('data',data=>{stderr+=data;});
  child.on('error',error=>{for(const request of pending.values())request.reject(error);pending.clear();});
  child.on('exit',code=>{if(pending.size){for(const request of pending.values())request.reject(Error(`SQLite adapter exited ${code}: ${stderr}`));pending.clear();}});
  createInterface({input:child.stdout}).on('line',line=>{const result=JSON.parse(line),request=pending.get(result.id);pending.delete(result.id);
    result.error?request.reject(Error(result.error)):request.resolve(result.rows);});
  t.after(()=>child.stdin.end());
  const sql=(statement,args=[])=>new Promise((resolve,reject)=>{
    if(fail?.(statement,args)){fail=null;reject(Error('injected write failure'));return;}
    const id=++sequence;pending.set(id,{resolve,reject});child.stdin.write(JSON.stringify({id,sql:statement,args})+'\n');
  });
  const store={version:0,executeSql:sql,createTransaction:async()=>{await sql('BEGIN');return{
    execute:sql,querySql:async(statement,args)=>resultSet(await sql(statement,args)),commit:()=>sql('COMMIT'),rollback:()=>sql('ROLLBACK')};}};
  const cache=new Map(), preferences=new Map(Object.entries(legacy)), preferenceWrites=[];
  const prefs={getPreferences:async(_,options)=>({get:async(key,fallback)=>preferences.get(options.name+'.'+key)??fallback,
    put:async(key,value)=>{preferenceWrites.push([options.name,key,value]);preferences.set(options.name+'.'+key,value);},flush:async()=>{}})};
  function load(file){
    file=path.resolve(root,file);if(cache.has(file))return cache.get(file);const module={exports:{}};cache.set(file,module.exports);
    const output=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
    const require=specifier=>specifier==='@kit.ArkData'?{relationalStore:{getRdbStore:async()=>store,SecurityLevel:{S1:1}},preferences:prefs}:load(path.resolve(path.dirname(file),specifier+'.ets'));
    vm.runInNewContext(output,{module,exports:module.exports,require,Date,console});return module.exports;
  }
  const {RdbSnapshotRepository}=load(path.join(root,'entry/src/main/ets/services/storage/RdbSnapshotRepository.ets'));
  return {repo:new RdbSnapshotRepository(),Repository:RdbSnapshotRepository,sql,store,load,preferences,preferenceWrites,setFailure:predicate=>{fail=predicate;}};
}
