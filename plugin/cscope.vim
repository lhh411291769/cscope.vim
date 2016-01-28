" vim: tabstop=2 shiftwidth=2 softtabstop=2 expandtab foldmethod=marker
"    Copyright: Copyright (C) 2012-2015 Brook Hong
"    License: The MIT License
"

if !exists('g:cscope_silent')
  let g:cscope_silent = 0
endif

if !exists('g:cscope_auto_update')
  let g:cscope_auto_update = 1
endif

if !exists('g:cscope_open_location')
  let g:cscope_open_location = 1
endif

if !exists('g:cscope_split_threshold')
  let g:cscope_split_threshold = 10000
endif

function! ToggleLocationList()
  let l:own = winnr()
  lw
  let l:cwn = winnr()
  if(l:cwn == l:own)
    if &buftype == 'quickfix'
      lclose
    elseif len(getloclist(winnr())) > 0
      lclose
    else
      echohl WarningMsg | echo "No location list." | echohl None
    endif
  endif
endfunction

if !exists('g:cscope_cmd')
  if executable('cscope')
    let g:cscope_cmd = 'cscope'
  else
    echo 'cscope: command not found'
    finish
  endif
endif

if !exists('g:cscope_interested_files')
  let files = readfile(expand("<sfile>:p:h")."/interested.txt")
  let g:cscope_interested_files = join(map(files, 'v:val."$"'), '\|')
endif

let s:cscope_vim_dir = substitute($HOME,'\\','/','g')."/.cscope.vim"
let s:index_file = s:cscope_vim_dir.'/index'

function! s:GetBestPath(dir)
  let f = substitute(a:dir,'\\','/','g')
  let bestDir = ""
  for d in keys(s:dbs)
    if stridx(f, d) == 0 && len(d) > len(bestDir)
      let bestDir = d
    endif
  endfor
  return bestDir
endfunction

function! s:ListFiles(dir)
  let d = []
  let f = []
  let cwd = a:dir
  let sl = &l:stl
  while cwd != ''
    let a = split(globpath(cwd, "*"), "\n")
    for fn in a
      if getftype(fn) == 'dir'
        call add(d, fn)
      elseif getftype(fn) != 'file'
        continue
      elseif fn !~? g:cscope_interested_files
        continue
      else
        if stridx(fn, ' ') != -1
          let fn = '"'.fn.'"'
        endif
        call add(f, fn)
      endif
    endfor
    let cwd = len(d) ? remove(d, 0) : ''
    sleep 1m | let &l:stl = 'Found '.len(f).' files, finding in '.cwd | redrawstatus
  endwhile
  sleep 1m | let &l:stl = sl | redrawstatus
  return f
endfunction

function! s:RmDBfiles()
  let odbs = split(globpath(s:cscope_vim_dir, "*"), "\n")
  for f in odbs
    call delete(f)
  endfor
endfunction

function! s:FlushIndex()
  let lines = []
  for d in keys(s:dbs)
    call add(lines, d.'|'.s:dbs[d]['id'].'|'.s:dbs[d]['loadtimes'].'|'.s:dbs[d]['dirty'].'|'.s:dbs[d]['project'])
    if index(s:projects, s:dbs[d]['project']) == -1
      call add(s:projects, s:dbs[d]['project'])
    endif
  endfor
  call writefile(lines, s:index_file)
endfunction

function! s:CheckNewFile(dir, newfile)
  let id = s:dbs[a:dir]['id']
  let cscope_files = s:cscope_vim_dir."/".id.".files"
  let files = readfile(cscope_files)
  if len(files) > g:cscope_split_threshold
    let cscope_files = s:cscope_vim_dir."/".id."_inc.files"
    if filereadable(cscope_files)
      let files = readfile(cscope_files)
    else
      let files = []
    endif
  endif
  if count(files, a:newfile) == 0
    call add(files, a:newfile)
    call writefile(files, cscope_files)
  endif
endfunction

function! s:_CreateDB(dir, init)
  let id = s:dbs[a:dir]['id']
  let cscope_files = s:cscope_vim_dir."/".id."_inc.files"
  let cscope_db = s:cscope_vim_dir.'/'.id.'_inc.db'
  if ! filereadable(cscope_files) || a:init
    let cscope_files = s:cscope_vim_dir."/".id.".files"
    let cscope_db = s:cscope_vim_dir.'/'.id.'.db'
    if ! filereadable(cscope_files)
      let files = <SID>ListFiles(a:dir)
      call writefile(files, cscope_files)
    endif
  endif
  exec 'cs kill '.cscope_db
  redir @x
  exec 'silent !'.g:cscope_cmd.' -b -i '.cscope_files.' -f'.cscope_db
  redi END
  if @x =~ "\nCommand terminated\n"
    echohl WarningMsg | echo "Failed to create cscope database for ".a:dir.", please check if " | echohl None
  else
    let s:dbs[a:dir]['dirty'] = 0
    exec 'cs add '.cscope_db
  endif
endfunction

function! s:CheckAbsolutePath(dir, defaultPath)
  let d = a:dir
  while 1
    if !isdirectory(d)
      echohl WarningMsg | echo "Please input a valid path." | echohl None
      let d = input("", a:defaultPath, 'dir')
    elseif (len(d) < 2 || (d[0] != '/' && d[1] != ':'))
      echohl WarningMsg | echo "Please input an absolute path." | echohl None
      let d = input("", a:defaultPath, 'dir')
    else
      break
    endif
  endwhile
  let d = substitute(d,'\\','/','g')
  let d = substitute(d,'/\+$','','')
  return d
endfunction

function! s:InitDB(dir)
  let id = localtime()
  let s:dbs[a:dir] = {}
  let s:dbs[a:dir]['id'] = id
  let s:dbs[a:dir]['loadtimes'] = 0
  let s:dbs[a:dir]['dirty'] = 0
  let s:dbs[a:dir]['project'] = 'default'
  call <SID>_CreateDB(a:dir, 1)
  call <SID>FlushIndex()
endfunction

function! s:LoadDB(dir)
"  commented by haihua.liu for load more then one DB
"  cs kill -1
  exe 'cs add '.s:cscope_vim_dir.'/'.s:dbs[a:dir]['id'].'.db'
  if filereadable(s:cscope_vim_dir.'/'.s:dbs[a:dir]['id'].'_inc.db')
    exe 'cs add '.s:cscope_vim_dir.'/'.s:dbs[a:dir]['id'].'_inc.db'
  endif
  let s:dbs[a:dir]['loadtimes'] = s:dbs[a:dir]['loadtimes']+1
  call <SID>FlushIndex()
endfunction

" TODO load all db files which are the same project except the default
function! s:AutoloadDB(dir)
  let m_dir = <SID>GetBestPath(a:dir)
  if m_dir == ""
    echohl WarningMsg | echo "Can not find proper cscope db, please input a path to generate cscope db for." | echohl None
    let m_dir = input("", a:dir, 'dir')
    if m_dir != ''
      let m_dir = <SID>CheckAbsolutePath(m_dir, a:dir)
      call <SID>InitDB(m_dir)
      call <SID>LoadDB(m_dir)
      call <SID>mergePorject(m_dir)
    endif
  else
" add by haihua.liu for project load db
    call <SID>loadProject(s:dbs[m_dir]['project'])
" end by haihua.liu
  endif
endfunction

function! s:getProject(d)
  return s:dbs[a:d]['project']
endfunction

function! s:setProject(d, project)
  s:dbs[a:d]['project'] = a:project
endfunction

function! s:getId(d)
  return s:dbs[a:d]['id']
endfunction

function! s:setId(d, id)
  s:dbs[a:d]['id'] = a:id
endfunction

function! s:mergeChildDB(directory)
  " merge child dbs which have the same project except
  " dbs with the 'default' project value
  " a:directory must be the key of s:dbs
  let dir_p = <SID>getProject(a:directory)
  if dir_p ==# 'default'
    return
  endif

  for d in keys(s:dbs)
    let d_p = <SID>getProject(d)
    if d_p ==# dir_p && len(a:directory) < len(d) && stridx(d, a:directory) == 0
      call <SID>clearDBs(d)
    endif
  endfor
endfunction

function! s:loadProject(project)
    if a:project != 'default'
      for d in keys(s:dbs)
        if a:project ==# s:dbs[d]['project']
          let id = s:dbs[d]['id']
          if cscope_connection(2, s:cscope_vim_dir.'/'.id.'.db') == 0
            call <SID>LoadDB(d)
          endif
        endif
      endfor
    endif
endfunction

" add by haihua.liu for add project info
function! AddDirectory()
  echohl WarningMsg | echo "please input: <directory> [project]" | echohl None
  let input = input("", expand('%:p:h'), 'dir')
  let inputarry = split(input, '')
  if len(inputarry) > 1
    let dir = inputarry[0]
    let project = inputarry[1]
    if index(s:projects, project) == -1
      call add(projects, project)
    endif
  elseif len(inputarry) > 0
    let dir = inputarry[0]
    let project = ""
  else
    return
  endif

  let m_dir = <SID>GetBestPath(dir)
  if m_dir == ""
    echohl WarningMsg | echo "\nNew dir for cscope, we will add it into database" | echohl None
    let m_dir = <SID>CheckAbsolutePath(dir, dir)
    call <SID>InitDB(m_dir)
    call <SID>LoadDB(m_dir)
    if project != ""
      let s:dbs[m_dir]['project'] = project
    endif
    call <SID>mergeChildDB(m_dir)
  else
    echohl WarningMsg | echo "\nDir exist for cscope, no need to add !" | echohl None
  endif
endfunction

function! DirOrId(A, L, P)
    let candidates = keys(s:dbs)
    for d in keys(s:dbs)
      call add(candidates, s:dbs[d]['id'])
    endfor
    call filter(candidates, 'v:val =~# "^" . a:A')
  return candidates
endfunction

function! Projects(A, L, P)
  return filter(s:projects, 'v:val =~# "^" . a:A')
endfunction

function! ModifyProject()
  let input = input("Please input directory or id: ", "", 'customlist,DirOrId')
  let project = input("Assigned to which project: ", "", 'customlist,Projects')
  call <SID>moveProject(input, project)
endfunction

let s:projects = []

function! s:moveProject(src, project)
  if a:src !~ '^\d\+$'
    let directory = a:src
  else
    let directory = <SID>getDirOfId(a:src)
  endif

  if directory != ""
    let directorys = []
    if directory[-1:] == '*'
      let directorys = filter(keys(s:dbs), 'v:val =~# "^" . directory[0:-2]')
    else
      let m_dir = <SID>GetBestPath(directory)
      call add(directorys, m_dir)
    endif

    if len(directorys) == 0 || index(directorys, '') != -1
      echohl WarningMsg | echo "\nNo proper cscope DB find, please retry!" | echohl None
      return
    else
      if a:project == ""
        echohl WarningMsg | echo "\nEmpty project name, return with no operation!" | echohl None
        return
      endif
      for m_dir in directorys
        let s:dbs[m_dir]['project'] = a:project
      endfor
      call <SID>FlushIndex()
    endif
  else
    echohl WarningMsg | echo "\nEmpty directory, return with no operation!" | echohl None
  endif
endfunction

function! s:getDirOfId(id)
  let dir = ""
  for d in keys(s:dbs)
    if a:id == s:dbs[d]['id']
      let dir = d
      break
    endif
  endfor
  return dir
endfunction


function! s:updateDBs(dirs)
  for d in a:dirs
    call <SID>_CreateDB(d, 0)
  endfor
  call <SID>FlushIndex()
endfunction

function! s:echo(msg)
  if g:cscope_silent == 0
    echo a:msg
  endif
endfunction

function! s:clearDBs(dir)
" commented for merge DB
" cs kill -1
  if a:dir == ""
    let s:dbs = {}
    call <SID>RmDBfiles()
  else
    let id = s:dbs[a:dir]['id']
    call delete(s:cscope_vim_dir."/".id.".files")
    call delete(s:cscope_vim_dir.'/'.id.'.db')
    call delete(s:cscope_vim_dir."/".id."_inc.files")
    call delete(s:cscope_vim_dir.'/'.id.'_inc.db')
    unlet s:dbs[a:dir]
  endif
  call <SID>FlushIndex()
endfunction

function! s:maxProjectLen()
  let max = 0
  for p in s:projects
    let max = len(p) > max ? len(p) : max
  endfor
  return max
endfunction

function! s:listDBs()
  let dirs = keys(s:dbs)
  if len(dirs) == 0
    echo "You have no cscope dbs now."
  else
    let max_p = <SID>maxProjectLen()
    let h_offset = max_p > 7 ? max_p - 6 : 1
    let c_offset = max_p > 7 ? max_p + 1 : 8
    let head = printf(" PROJECT%-".h_offset."sID         LOADTIMES PATH", " ")
    let s = [head]
    for project in s:projects
      for d in dirs
        if project ==# s:dbs[d]['project']
          let id = s:dbs[d]['id']
          if cscope_connection(2, s:cscope_vim_dir.'/'.id.'.db') == 1
            let l = printf("*%-".c_offset."s%-11d%-10d%s", s:dbs[d]['project'], id, s:dbs[d]['loadtimes'], d)
          else
            let l = printf(" %-".c_offset."s%-11d%-10d%s", s:dbs[d]['project'], id, s:dbs[d]['loadtimes'], d)
          endif
          call add(s, l)
        endif
      endfor
    endfor
    echo join(s, "\n")
  endif
endfunction

function! s:loadIndex()
  let s:dbs = {}
  if ! isdirectory(s:cscope_vim_dir)
    call mkdir(s:cscope_vim_dir)
  elseif filereadable(s:index_file)
    let idx = readfile(s:index_file)
    for i in idx
      let e = split(i, '|')
      if len(e) == 0
        call delete(s:index_file)
        call <SID>RmDBfiles()
      else
        let db_file = s:cscope_vim_dir.'/'.e[1].'.db'
        if filereadable(db_file)
          if isdirectory(e[0])
            let s:dbs[e[0]] = {}
            let s:dbs[e[0]]['id'] = e[1]
            let s:dbs[e[0]]['loadtimes'] = e[2]
            let s:dbs[e[0]]['dirty'] = (len(e) > 3) ? e[3] :0
            if len(e) > 4
              let s:dbs[e[0]]['project'] = e[4]
              if index(s:projects, e[4]) == -1
                call add(s:projects, e[4])
              endif
            else
              let s:dbs[e[0]]['project'] = "default"
            endif
          else
            call delete(db_file)
          endif
        endif
      endif
    endfor
  else
    call <SID>RmDBfiles()
  endif
endfunction

function! s:preloadDB()
  let dirs = split(g:cscope_preload_path, ';')
  for m_dir in dirs
    let m_dir = <SID>CheckAbsolutePath(m_dir, m_dir)
    if ! has_key(s:dbs, m_dir)
      call <SID>InitDB(m_dir)
    endif
    call <SID>LoadDB(m_dir)
  endfor
endfunction

function! CscopeFind(action, word)
  let dirtyDirs = []
  for d in keys(s:dbs)
    if s:dbs[d]['dirty'] == 1
      call add(dirtyDirs, d)
    endif
  endfor
  if len(dirtyDirs) > 0
    call <SID>updateDBs(dirtyDirs)
  endif
  call <SID>AutoloadDB(expand('%:p:h'))
  try
    exe ':lcs f '.a:action.' '.a:word
    if g:cscope_open_location == 1
      lw
    endif
  catch
    echohl WarningMsg | echo 'Can not find '.a:word.' with querytype as '.a:action.'.' | echohl None
  endtry
endfunction

function! CscopeFindInteractive(pat)
    call inputsave()
    let qt = input("\nChoose a querytype for '".a:pat."'(:help cscope-find)\n  c: functions calling this function\n  d: functions called by this function\n  e: this egrep pattern\n  f: this file\n  g: this definition\n  i: files #including this file\n  s: this C symbol\n  t: this text string\n\n  or\n  <querytype><pattern> to query `pattern` instead of '".a:pat."' as `querytype`, Ex. `smain` to query a C symbol named 'main'.\n> ")
    call inputrestore()
    if len(qt) > 1
        call CscopeFind(qt[0], qt[1:])
    elseif len(qt) > 0
        call CscopeFind(qt, a:pat)
    endif
    call feedkeys("\<CR>")
endfunction

function! s:onChange()
  if expand('%:t') =~? g:cscope_interested_files
    let m_dir = <SID>GetBestPath(expand('%:p:h'))
    if m_dir != ""
      let s:dbs[m_dir]['dirty'] = 1
      call <SID>FlushIndex()
      call <SID>CheckNewFile(m_dir, expand('%:p'))
      redraw
      call <SID>echo('Your cscope db will be updated automatically, you can turn off this message by setting g:cscope_silent 1.')
    endif
  endif
endfunction

function! CscopeUpdateDB()
  call <SID>updateDBs(keys(s:dbs))
endfunction
if exists('g:cscope_preload_path')
  call <SID>preloadDB()
endif

if g:cscope_auto_update == 1
  au BufWritePost * call <SID>onChange()
endif

set cscopequickfix=s-,g-,d-,c-,t-,e-,f-,i-

function! s:listDirs(A,L,P)
  return keys(s:dbs)
endfunction
com! -nargs=? -complete=customlist,<SID>listDirs CscopeClear call <SID>clearDBs("<args>")

com! -nargs=0 CscopeList call <SID>listDBs()
call <SID>loadIndex()
