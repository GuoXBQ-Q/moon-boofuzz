// SPDX-License-Identifier: GPL-2.0-only
// Shared, self-contained dark console assets. No external fonts or scripts.

///|
const PAGE_CSS : String =
  #|:root{color-scheme:dark;--bg:#101417;--surface:#171d22;--surface-raised:#1c242a;--line:#2a343d;--text:#edf2f4;--muted:#97a6b2;--accent:#8bd5bf;--accent-bg:#203a32;--danger:#f29b9b;--amber:#e8c48b;--mono:"Cascadia Code","SFMono-Regular",Consolas,monospace}
  #|*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.55 "Segoe UI",system-ui,-apple-system,sans-serif;-webkit-font-smoothing:antialiased}
  #|a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}button,input,select,textarea{font:inherit}button,a,input,select,textarea{outline-offset:4px}
  #|:focus-visible{outline:2px solid var(--accent)}[hidden]{display:none!important}
  #|.app-topbar{border-bottom:1px solid var(--line);background:#13191d}.topbar-inner{max-width:1200px;margin:auto;padding:18px 28px;display:flex;align-items:center;gap:24px}
  #|.brand{display:flex;align-items:center;gap:10px;color:var(--text);font-weight:650;font-size:17px;letter-spacing:-.5px}.brand:hover{text-decoration:none}.brand-mark{display:grid;place-items:center;width:30px;height:30px;background:var(--accent);color:#13211c;border-radius:8px;font:700 19px var(--mono)}
  #|.topbar-context{font-size:12px;color:var(--muted);border-left:1px solid var(--line);padding-left:24px}.local-label{margin-left:auto;display:flex;align-items:center;gap:8px;color:var(--muted);font:11px var(--mono);letter-spacing:.5px}.local-dot{width:6px;height:6px;border-radius:50%;background:var(--accent)}
  #|.app-shell{max-width:1200px;margin:auto;padding:36px 28px 48px}.page-heading{display:flex;align-items:flex-start;justify-content:space-between;gap:24px;margin-bottom:28px}.eyebrow{color:var(--accent);font:11px var(--mono);letter-spacing:1.5px;margin-bottom:10px;text-transform:uppercase}
  #|h1{font-size:32px;line-height:1.2;letter-spacing:-1px;font-weight:600;margin:0 0 12px}h2{font-size:16px;letter-spacing:-.2px;font-weight:600;margin:0}h3{font-size:14px;font-weight:600;margin:0}.page-description{margin:0;color:var(--muted);max-width:680px}.muted,.hint{color:var(--muted)}.hint{font-size:12px;margin:8px 0 0}
  #|.heading-actions,.actions{display:flex;align-items:center;gap:12px;flex-wrap:wrap}.heading-actions{padding-top:25px}.button,.input[type=submit]{display:inline-flex;align-items:center;justify-content:center;gap:8px;border:1px solid var(--line);border-radius:7px;min-height:38px;padding:8px 15px;background:#222c33;color:var(--text);font-size:13px;font-weight:550;cursor:pointer;white-space:nowrap}
  #|.button:hover,.input[type=submit]:hover{background:#2a353d;text-decoration:none}.button.primary,.input[type=submit].primary{background:var(--accent);border-color:var(--accent);color:#12261e}.button.primary:hover{background:#a1e2ce}.button.ghost{background:transparent;color:var(--muted)}.button.small{min-height:30px;padding:5px 10px;font-size:12px}button:disabled{cursor:default;opacity:.5}
  #|.status{display:inline-flex;align-items:center;gap:7px;border-radius:5px;border:1px solid #345447;background:var(--accent-bg);color:var(--accent);font:11px var(--mono);padding:5px 9px;text-transform:uppercase;letter-spacing:.4px}.status:before{content:"";width:5px;height:5px;border-radius:50%;background:currentColor}.status.paused{color:var(--amber);background:#382d20;border-color:#67523a}.status.finished{color:#b6c7d6;background:#26313b;border-color:#3b4b59}
  #|.panel{background:var(--surface);border:1px solid var(--line);border-radius:10px;min-width:0}.panel-head{padding:18px 22px;border-bottom:1px solid var(--line);display:flex;align-items:center;justify-content:space-between;gap:16px}.panel-body{padding:22px}.panel-head .hint{margin-top:4px}.panel-head .actions{flex-wrap:nowrap}
  #|.metrics{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));margin-bottom:20px}.metrics.offline{grid-template-columns:repeat(2,minmax(0,1fr))}.metric{padding:22px 24px;min-width:0;border-right:1px solid var(--line)}.metric:last-child{border:0}.metric-label{color:var(--muted);font-size:12px;margin-bottom:8px}.metric-value{font-size:30px;line-height:1.2;letter-spacing:-.7px;font-weight:550;font-variant-numeric:tabular-nums}.metric-value.error{color:var(--danger)}.metric-value.small-value{font-size:25px}.metric-caption{color:var(--muted);font-size:11px;margin-top:8px}
  #|.overview-grid{display:grid;grid-template-columns:1.65fr 1fr;gap:20px;margin-bottom:26px}.run-progress{width:100%;height:7px;appearance:none;border:0;border-radius:8px;overflow:hidden;background:#2c373e;accent-color:var(--accent)}.run-progress::-webkit-progress-bar{background:#2c373e}.run-progress::-webkit-progress-value{background:var(--accent)}.run-progress::-moz-progress-bar{background:var(--accent)}
  #|.progress-labels{display:flex;justify-content:space-between;gap:16px;font-size:12px;margin-bottom:14px;color:var(--muted)}.progress-labels strong{color:var(--text);font-weight:500}.run-context{display:flex;justify-content:space-between;gap:16px;margin-top:20px;font-size:12px;color:var(--muted)}.run-context code{color:var(--text);word-break:break-all}
  #|.lookup{display:flex;align-items:end;gap:10px}.lookup .field{flex:1;margin:0}.lookup input{width:100%}.connection{font-size:11px;color:var(--muted);margin-top:14px}.connection.stale{color:var(--amber)}
  #|.section-heading{display:flex;justify-content:space-between;align-items:center;gap:18px;margin-bottom:14px}.section-heading p{margin:4px 0 0}.count-label{background:#273139;color:var(--muted);border:1px solid var(--line);border-radius:4px;font:11px var(--mono);padding:2px 6px;margin-left:9px}
  #|.field{display:flex;flex-direction:column;gap:7px;margin-bottom:16px;min-width:0}.field label,.field-label{font-size:12px;color:#c4cfd6;font-weight:500}.field-row{display:grid;grid-template-columns:1fr 1fr;gap:14px}
  #|input:not([type=checkbox]):not([type=submit]):not([type=hidden]),select,textarea{border:1px solid #384550;border-radius:6px;background:#11171c;color:var(--text);padding:10px 11px;min-width:0}.input{width:100%}input:hover,select:hover,textarea:hover{border-color:#4c606c}input[type=checkbox]{width:16px;height:16px;accent-color:var(--accent);cursor:pointer}input::placeholder,textarea::placeholder{color:#697c89}
  #|select{cursor:pointer;width:100%}textarea{width:100%;resize:vertical;display:block;font:12px/1.7 var(--mono)}code,.mono,.fixed{font-family:var(--mono)}code{font-size:12px}.code-input{min-height:290px;padding:16px!important;tab-size:2}.code-input:focus{border-color:var(--accent)}
  #|.table-wrap{overflow-x:auto}.data-table,.summary{border-collapse:collapse;width:100%;text-align:left;font-size:13px}.data-table th,.summary th{padding:12px 20px;font-size:11px;font-weight:500;color:var(--muted);background:#141b20;border-bottom:1px solid var(--line)}.data-table td,.summary td{padding:15px 20px;border-bottom:1px solid var(--line);vertical-align:top}.data-table tbody tr:last-child td,.summary tbody tr:last-child td{border:0}.data-table tbody tr:hover{background:#1c252c}.case-link{font:12px var(--mono);white-space:nowrap}.failure-reason{font:12px/1.6 var(--mono);color:#dbb1b1;overflow-wrap:anywhere}.row-action{white-space:nowrap;color:var(--muted);font-size:12px}.search-input{min-width:260px}.empty-state{padding:42px 24px;text-align:center;color:var(--muted)}.empty-state strong{display:block;color:var(--text);font-size:15px;font-weight:550;margin-bottom:8px}.empty-state p{margin:0 auto;max-width:520px;font-size:13px}.empty-symbol{display:inline-grid;place-items:center;width:40px;height:40px;border-radius:50%;border:1px solid var(--line);color:var(--accent);margin-bottom:14px;font-size:20px}
  #|.app-footer{display:flex;justify-content:space-between;gap:16px;border-top:1px solid var(--line);margin-top:30px;padding-top:18px;color:#778c99;font-size:11px}.app-footer code{font-size:11px}
  #|.steps{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));padding:0;margin:0 0 28px;list-style:none;border:1px solid var(--line);border-radius:8px;overflow:hidden;background:#141a1f}.step{display:flex;gap:12px;align-items:center;padding:15px 20px;border-right:1px solid var(--line);color:#788c99;font-size:12px}.step:last-child{border:0}.step-number{font:11px var(--mono);border:1px solid var(--line);border-radius:4px;padding:3px 6px}.step.active{color:var(--text);background:#1b2a26}.step.active .step-number{color:var(--accent);border-color:#3d6354}.step.done{color:#b1c3bc}
  #|.builder-grid{display:grid;grid-template-columns:minmax(0,1.8fr) minmax(280px,1fr);gap:20px}.builder-grid .settings-panel .panel-body{padding:20px}.wizard-actions{grid-column:1/-1;display:flex;align-items:center;justify-content:space-between;gap:16px;padding-top:2px}.wizard-actions .hint{margin:0}.request-panel .panel-body{padding:18px}.request-panel .panel-foot{padding:13px 18px;border-top:1px solid var(--line);color:var(--muted);font:11px var(--mono)}
  #|.notice{background:#202c30;border:1px solid #334b53;border-radius:7px;padding:14px 17px;font-size:12px;color:#c0d0d6;margin:0 0 18px}.notice.warning{background:#2d2820;border-color:#5a4933;color:#dbc8aa}.notice.error{background:#2e2326;border-color:#5e363d;color:#edb4b9}.notice p{margin:0}
  #|.segments-table{min-width:1030px;table-layout:fixed}.segments-table th,.segments-table td{padding:13px 14px}.segments-table th:first-child{width:55px}.segments-table th:nth-child(2){width:145px}.segments-table th:nth-child(3){width:245px}.segments-table th:nth-child(4){width:300px}.segments-table textarea{min-height:70px}.segments-table tr.is-selected{background:#1c2b26}.segment-value{display:block;white-space:pre-wrap;word-break:break-all;max-height:100px;overflow:auto;color:#bacbd4;font-size:11px}.segment-name{font-size:12px;font-weight:550}.primitive-params{margin-top:8px;display:flex;align-items:center;gap:6px;flex-wrap:wrap;color:var(--muted);font:11px var(--mono)}.primitive-params input{width:65px!important;padding:6px!important}.primitive-params select{width:90px!important;padding:6px!important}
  #|.result-grid{display:grid;grid-template-columns:minmax(0,1.85fr) minmax(280px,1fr);gap:20px;margin-bottom:25px}.definition-json{min-height:420px!important;max-height:650px;font:12px/1.7 var(--mono);padding:17px!important;border-radius:0!important;border:0!important;background:#11171c!important}.json-actions{display:flex;gap:10px;align-items:center;padding:14px 18px;border-top:1px solid var(--line)}.copy-status{color:var(--accent);font-size:12px;min-height:18px}.result-stat{font-size:44px;letter-spacing:-1.5px;color:var(--accent);line-height:1.1;font-weight:500;margin:12px 0 8px}.result-target{font:12px var(--mono);word-break:break-all}.result-notes{padding-left:18px;color:var(--muted);font-size:12px;line-height:1.85}
  #|.payload-preview{border:1px solid var(--line);border-radius:8px;background:var(--surface);margin-bottom:10px;overflow:hidden}.payload-preview summary{padding:15px 20px;cursor:pointer;font-size:12px;font-weight:550;list-style-position:inside}.payload-preview[open] summary{border-bottom:1px solid var(--line)}.payload-preview pre{padding:18px 20px;margin:0;white-space:pre-wrap;overflow-wrap:anywhere;max-height:200px;overflow:auto;font:12px/1.7 var(--mono);color:#c4d4db;background:#12191e}.payload-preview .hex-preview{padding:14px 20px;border-top:1px solid var(--line);font:11px/1.7 var(--mono);color:#829ca9;overflow-wrap:anywhere;max-height:100px;overflow:auto}
  #|.log-toolbar{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:14px 18px;border-bottom:1px solid var(--line);flex-wrap:wrap}.log-filters{display:flex;gap:4px;flex-wrap:wrap}.log-filters button{background:transparent;color:var(--muted);border:1px solid transparent;padding:6px 10px;border-radius:5px;font:11px var(--mono);cursor:pointer}.log-filters button[aria-pressed=true]{color:var(--accent);border-color:#385247;background:#20332b}.log-lines{background:#11181d;border-radius:0 0 10px 10px;overflow:hidden}.log-line{display:grid;grid-template-columns:58px minmax(0,1fr);gap:14px;align-items:start;padding:13px 20px;border-bottom:1px solid #25313a}.log-line:last-child{border:0}.log-marker{font:10px var(--mono);color:var(--muted);padding-top:3px;letter-spacing:.3px}.log-text{font:12px/1.65 var(--mono);margin:0;white-space:pre-wrap;overflow-wrap:anywhere;color:#b6c6cf}.log-case{background:#1a252c}.log-case .log-text,.log-step .log-text{color:#e0e9ed}.log-send .log-marker{color:#86c7b0}.log-receive .log-marker{color:#8dbadb}.log-fail .log-marker,.log-error .log-marker{color:var(--danger)}.log-fail,.log-error{background:#251d22}.log-fail .log-text,.log-error .log-text{color:#eab0b7}.log-pass .log-marker{color:var(--accent)}.back-link{display:inline-block;color:var(--muted);font-size:12px;margin-bottom:20px}
  #|.log-send .log-text,.log-receive .log-text{max-height:240px;overflow:auto}
  #|@media(max-width:900px){.app-shell{padding:28px 20px 36px}.topbar-inner{padding:16px 20px}.overview-grid,.builder-grid,.result-grid{grid-template-columns:1fr}.metrics{grid-template-columns:repeat(2,minmax(0,1fr))}.metric:nth-child(2){border:0}.metric:nth-child(-n+2){border-bottom:1px solid var(--line)}.metrics.offline .metric{border-bottom:0}.builder-grid .settings-panel .field-row{grid-template-columns:repeat(2,minmax(0,1fr))}.wizard-actions{grid-column:auto}.definition-json{min-height:330px!important}}
  #|@media(max-width:580px){.topbar-context{display:none}.local-label{font-size:9px}.brand{font-size:15px}.page-heading{display:block}.heading-actions{padding-top:4px}h1{font-size:27px}.metric{padding:18px}.metric-value{font-size:26px}.steps .step{padding:13px 10px;gap:7px;font-size:11px}.step-number{padding:2px 4px}.section-heading{align-items:flex-start;flex-direction:column}.search-input{width:100%;min-width:0}.panel-head,.panel-body{padding:18px}.data-table th,.data-table td{padding:13px 16px}.row-action,.data-table th:last-child,.data-table td:last-child{display:none}.log-line{grid-template-columns:40px minmax(0,1fr);gap:8px;padding:12px}.app-footer{flex-direction:column;gap:4px}.wizard-actions{align-items:stretch;flex-direction:column}.wizard-actions .button{width:100%}.field-row{gap:10px}}
  #|@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto!important;transition:none!important;animation:none!important}}

///|
const PAGE_SCRIPT : String =
  #|<script>
  #|(function(){
  #|'use strict';
  #|function text(id,value){var node=document.getElementById(id);if(node)node.textContent=value;}
  #|window.uiCopy=async function(value,statusId){
  #| var status=document.getElementById(statusId),ok=false;
  #| try{if(navigator.clipboard&&navigator.clipboard.writeText){await navigator.clipboard.writeText(value);ok=true;}}catch(e){}
  #| if(!ok){var t=document.createElement('textarea');t.value=value;t.style.position='fixed';t.style.opacity='0';document.body.appendChild(t);t.select();try{ok=document.execCommand('copy');}catch(e){}t.remove();}
  #| if(status)status.textContent=ok?'Copied to clipboard':'Copy unavailable. Select the text to copy it.';
  #|};
  #|var lookup=document.getElementById('case-lookup');
  #|if(lookup)lookup.addEventListener('submit',function(e){e.preventDefault();var input=document.getElementById('case-index');if(!/^\d{1,9}$/.test(input.value)){input.setCustomValidity('Enter a case index from 0 to 999999999.');input.reportValidity();return;}input.setCustomValidity('');location.assign('/test-case/'+Number(input.value));});
  #|var filter=document.getElementById('failure-filter');
  #|function filterFailures(){var query=filter?filter.value.trim().toLowerCase():'';var rows=document.querySelectorAll('#failure-rows tr'),shown=0;rows.forEach(function(row){row.hidden=query&&!row.textContent.toLowerCase().includes(query);if(!row.hidden)shown++;});var empty=document.getElementById('failure-empty');if(empty)empty.hidden=rows.length>0&&shown>0;var title=document.getElementById('failure-empty-title');if(title)title.textContent=rows.length===0?'No failures recorded':'No matching cases';var desc=document.getElementById('failure-empty-description');if(desc)desc.textContent=rows.length===0?'Failure records will appear here with a link to their traffic log.':'Try a different case index or reason.';}
  #|if(filter)filter.addEventListener('input',filterFailures);
  #|var logButtons=document.querySelectorAll('[data-log-filter]');
  #|logButtons.forEach(function(button){button.addEventListener('click',function(){var group=button.dataset.logFilter,shown=0;logButtons.forEach(function(b){b.setAttribute('aria-pressed',String(b===button));});document.querySelectorAll('#case-log .log-line').forEach(function(row){var c=row.classList;var visible=group==='all'||(group==='traffic'&&(c.contains('log-send')||c.contains('log-receive')))||(group==='checks'&&(c.contains('log-check')||c.contains('log-pass')||c.contains('log-fail')))||(group==='errors'&&(c.contains('log-error')||c.contains('log-fail')));row.hidden=!visible;if(visible)shown++;});var empty=document.getElementById('log-empty');if(empty)empty.hidden=shown>0;});});
  #|var copyLog=document.getElementById('copy-log');
  #|if(copyLog)copyLog.addEventListener('click',function(){var lines=Array.from(document.querySelectorAll('#case-log .log-line')).filter(function(r){return !r.hidden;}).map(function(r){return r.querySelector('.log-text').textContent;});window.uiCopy(lines.join('\n'),'log-copy-status');});
  #|var overview=document.getElementById('run-overview');if(!overview)return;
  #|var offline=overview.dataset.mode==='finished',timer=null;
  #|filterFailures();
  #|function renderFailures(failures){
  #| var body=document.getElementById('failure-rows');body.replaceChildren();
  #| failures.slice().sort(function(a,b){return Number(a.key)-Number(b.key);}).forEach(function(item){var tr=document.createElement('tr'),id=document.createElement('td'),reason=document.createElement('td'),action=document.createElement('td'),link=document.createElement('a'),open=document.createElement('a');link.href='/test-case/'+Number(item.key);link.className='case-link';link.textContent=String(item.key);id.appendChild(link);reason.className='failure-reason';reason.textContent=(item.reasons||[]).join(' | ');open.href=link.href;open.textContent='View log →';open.className='row-action';action.appendChild(open);tr.append(id,reason,action);body.appendChild(tr);});
  #| text('failure-count',failures.length);text('failure-count-heading',failures.length);filterFailures();
  #|}
  #|async function refresh(){
  #| var controller=new AbortController(),timeout=setTimeout(function(){controller.abort();},8000);
  #| try{
  #|  var response=await fetch('/api/current-run',{signal:controller.signal,cache:'no-store'});if(!response.ok)throw new Error('Unavailable');
  #|  var data=await response.json(),s=data.session_info,count=Number(s.current_index)||0,total=Number(s.num_mutations)||0,ratio=total>0?Math.max(0,Math.min(count/total,1)):0;
  #|  text('current_index',count.toLocaleString('en-US'));text('num_mutations',total>0?total.toLocaleString('en-US'):'Unbounded');text('run_time',Math.round(Number(s.runtime)||0)+'s');text('exec_speed',(Number(s.exec_speed)||0).toFixed(1)+'/s');text('current_test_case_name',s.current_test_case_name||'Waiting for the first case');text('current_element',s.current_element||'—');
  #|  var indicator=document.getElementById('is_paused_indicator'),state=s.state==='finished'?'finished':s.is_paused?'paused':'running';indicator.className='status '+state;indicator.textContent=state==='finished'?'Saved run':state==='paused'?'Paused':'Running';
  #|  var pause=document.getElementById('pause-button');if(pause){pause.textContent=s.is_paused?'Resume run':'Pause run';pause.disabled=state==='finished';}
  #|  var bar=document.getElementById('progress_bar_total');if(bar){if(total>0)bar.value=ratio*100;else bar.removeAttribute('value');}
  #|  text('progress_percentage_total',total>0?(ratio*100).toFixed(1)+'%':'No fixed limit');renderFailures(s.crashes||[]);
  #|  var connection=document.getElementById('connection-status');connection.className='connection';connection.textContent='Connected · updates every 2 seconds';
  #|  if(state==='finished')offline=true;
  #| }catch(e){var connection=document.getElementById('connection-status');if(connection){connection.className='connection stale';connection.textContent='Waiting for runner · retrying automatically';}}
  #| finally{clearTimeout(timeout);if(!offline)timer=setTimeout(refresh,2000);}
  #|}
  #|if(!offline)timer=setTimeout(refresh,2000);
  #|window.addEventListener('pagehide',function(){if(timer)clearTimeout(timer);});
  #|})();
  #|</script>

///|
const CONVERT_SCRIPT : String =
  #|<script>
  #|function syncPrimitive(id){
  #| var select=document.getElementsByName('p_'+id)[0];if(!select)return;
  #| ['integer','bytes','random'].forEach(function(kind){var node=document.getElementById('params_'+kind+'_'+id);if(node)node.hidden=select.value!==kind;});
  #|}
  #|function syncReadPolicy(){var policy=document.getElementById('read-policy'),field=document.getElementById('fixed-length-field');if(policy&&field)field.hidden=policy.value!=='fixed';}
  #|function syncSelections(){var selected=0;document.querySelectorAll('input[type=checkbox][name^="f_"]').forEach(function(input){if(input.checked)selected++;input.closest('tr').classList.toggle('is-selected',input.checked);});var count=document.getElementById('selected-count');if(count)count.textContent=selected+' selected';}
  #|function copyDefinition(){var input=document.getElementById('definition-json');if(input)window.uiCopy(input.value,'copy-status');}
  #|function downloadDefinition(){
  #| var input=document.getElementById('definition-json'),name=document.getElementById('download-name');if(!input)return;
  #| var url=URL.createObjectURL(new Blob([input.value],{type:'application/json'})),link=document.createElement('a');link.href=url;link.download=((name&&name.value)||'definition')+'.json';document.body.appendChild(link);link.click();link.remove();setTimeout(function(){URL.revokeObjectURL(url);},1000);var status=document.getElementById('copy-status');if(status)status.textContent='Download started';
  #|}
  #|document.querySelectorAll('select[name^="p_"]').forEach(function(select){if(!select.name.includes('_width')&&!select.name.includes('_endian'))syncPrimitive(select.name.slice(2));});
  #|document.querySelectorAll('input[type=checkbox][name^="f_"]').forEach(function(input){input.addEventListener('change',syncSelections);});
  #|document.querySelectorAll('[data-select-fields]').forEach(function(button){button.addEventListener('click',function(){document.querySelectorAll('input[type=checkbox][name^="f_"]').forEach(function(input){input.checked=button.dataset.selectFields==='all';});syncSelections();});});
  #|var sample=document.getElementById('use-sample');if(sample)sample.addEventListener('click',function(){var input=document.getElementById('raw-request');input.value=input.placeholder;input.focus();});
  #|syncReadPolicy();syncSelections();
  #|</script>

///|
fn page_start(title : String, context : String, home : String) -> String {
  "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>" +
  html_escape(title) +
  " · moon-boofuzz</title><style>" +
  PAGE_CSS +
  "</style></head><body><header class=\"app-topbar\"><div class=\"topbar-inner\"><a class=\"brand\" href=\"" +
  home +
  "\"><span class=\"brand-mark\" aria-hidden=\"true\">m.</span>moon-boofuzz</a><span class=\"topbar-context\">" +
  html_escape(context) +
  "</span><span class=\"local-label\"><span class=\"local-dot\" aria-hidden=\"true\"></span>LOCAL WORKSPACE</span></div></header><main class=\"app-shell\">"
}

///|
fn page_end(script : String) -> String {
  "<footer class=\"app-footer\"><span>moon-boofuzz · Protocol testing</span><span>Local workspace / Built with MoonBit</span></footer></main>" +
  script +
  "</body></html>"
}

///|
fn page_heading(
  kicker : String,
  title : String,
  description : String,
  actions : String,
) -> String {
  "<div class=\"page-heading\"><div><div class=\"eyebrow\">" +
  html_escape(kicker) +
  "</div><h1>" +
  html_escape(title) +
  "</h1><p class=\"page-description\">" +
  html_escape(description) +
  "</p></div><div class=\"heading-actions\">" +
  actions +
  "</div></div>"
}

///|
fn converter_steps(stage : Int) -> String {
  let out = StringBuilder()
  out.write_string("<ol class=\"steps\" aria-label=\"Conversion progress\">")
  for i, label in ["Request", "Mutations", "Definition"] {
    let index = i + 1
    let state = if index == stage {
      "active"
    } else if index < stage {
      "done"
    } else {
      ""
    }
    out.write_string(
      "<li class=\"step " +
      state +
      "\"" +
      (if index == stage { " aria-current=\"step\"" } else { "" }) +
      "><span class=\"step-number\">0" +
      index.to_string() +
      "</span>" +
      label +
      "</li>",
    )
  }
  out.write_string("</ol>")
  out.to_string()
}
