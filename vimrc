"
" BoGo preferences
"
set expandtab
set       tabstop=2
set   softtabstop=2
set    shiftwidth=2

"
"   show statusline only with 2 or more open windows
set laststatus=1

set mouse=a

set backupcopy=yes
"write backup separately, don't rename = keep original file = support file watchers such as dev servers"


:nnoremap <leader>ce :Copilot enable<CR>
:nnoremap <leader>cd :Copilot disable<CR>
:inoremap <leader>cd <Esc>:Copilot disable<CR>a

let g:copilot_enabled = v:false

" remember cursor location
:au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") && &ft !~# 'commit' | exe "normal! g`\"" | endif

" improve the chance to catch external edits to an open file
set autoread
autocmd FocusGained,BufEnter,CursorHold * checktime

"
" INCLUDE in ~/.vimrc as follows (uncomment last line):
"
" synchronizing BoGo settings across devices
"
"source ~/managed-scripts/vimrc
