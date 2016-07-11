" KEYBINDING {{{
" Change leader to space
let mapleader = "\<Space>"
" Open Nerdtree with leader-e
map <leader>e :NERDTreeToggle<CR>
" Open undotree with leader-u
map <leader>u :UndotreeToggle<CR>
" save session (windows/buffers). Open with vim -S
nnoremap <leader>s :mksession<CR>
" Send current selected text to interpreter.
map <leader>n :SlimuxREPLSendLine<CR>
" Opens CtrlP
map <leader>p :CtrlP<CR>
" Opens ack.vim
map <leader>a :Ack!<Space>
" }}}

" UNDO {{{
set undodir=~/.vim/undodir
set undofile
set undolevels=1000 "maximum number of changes that can be undone
set undoreload=10000 "maximum number lines to save for undo on a buffer reload
" }}}

" BASIC SETTINGS {{{
" Load pathogen plugin system
execute pathogen#infect() 
" Turn on auto indenting
filetype plugin indent on
" enable sytax processing
syntax on
" set the default encoding
set encoding=utf-8
" turn on line numbers
set number
" highlight current line
set cursorline
" display the list of autocomplete for command menu
set wildmenu
" highlight matching parentheses/braces/brackets 
set showmatch
" Check the final line in a file for a modeline
set modelines=1
" Color Scheme
colorscheme pyte
" Ignore files in wildcard search
set wildignore+=*/tmp/*,*.so,*.swp,*.zip
" }}}

" PLUGIN SETTINGS {{{
" Let airline use powerline fonts 
let g:airline_powerline_fonts = 1
" The airline theme
let g:airline_theme='bubblegum'
" Have NERDTree ignore some file types
let NERDTreeIgnore = ['\.pyc$']
" CtrlP ignore some directories
let g:ctrlp_custom_ignore = '\v[\/]\.(git|hg|svn)$'
" Tell Ack.vim to use ag
if executable('ag')
        let g:ackprg = 'ag --vimgrep --smart-case'
endif
" }}}

" TABS & SPACES {{{
" set the visual spaces per tab
set tabstop=4
" number of spaces in tab when editing
set softtabstop=4
" tabs are spaces
set expandtab
" }}}

" SEARCH {{{
" search as characters are entered
set incsearch
" highlight matches
set hlsearch
" turn off search highlight
nnoremap <leader><space> :nohlsearch<CR>
"}}}

" FOLDING {{{
" enable folding
set foldenable
" open most folds by default
set foldlevelstart=10
" fold based on indent level
set foldmethod=indent
" }}}

" LANGUAGE SETTINGS {{{
augroup configgroup
    autocmd!
    autocmd VimEnter * highlight clear SignColumn
    autocmd FileType java setlocal noexpandtab
    autocmd FileType java setlocal list
    autocmd FileType java setlocal listchars=tab:+\ ,eol:-
    autocmd FileType java setlocal formatprg=par\ -w80\ -T4
    autocmd FileType php setlocal expandtab
    autocmd FileType php setlocal list
    autocmd FileType php setlocal listchars=tab:+\ ,eol:-
    autocmd FileType php setlocal formatprg=par\ -w80\ -T4
    autocmd FileType ruby setlocal tabstop=2
    autocmd FileType ruby setlocal shiftwidth=2
    autocmd FileType ruby setlocal softtabstop=2
    autocmd FileType ruby setlocal commentstring=#\ %s
    autocmd FileType python setlocal commentstring=#\ %s
    autocmd BufEnter *.cls setlocal filetype=java
    autocmd BufEnter *.zsh-theme setlocal filetype=zsh
    autocmd BufEnter Makefile setlocal noexpandtab
    autocmd BufEnter *.sh setlocal tabstop=2
    autocmd BufEnter *.sh setlocal shiftwidth=2
    autocmd BufEnter *.sh setlocal softtabstop=2
augroup END
" }}}

" BACKUP {{{
" enable backups
set backup
set writebackup
" location for the backup files to be stored
set backupdir=~/.vim-tmp,~/.tmp,~/tmp,/var/tmp,/tmp
" any file in these folders won't be backed up
set backupskip=/tmp/*,/private/tmp/* 
" Folders to save the swap file to
set directory=~/.vim-tmp,~/.tmp,~/tmp,/var/tmp,/tmp
" }}}

" CUSTOM FUNCTIONS {{{
" strips trailing whitespace at the end of files. this
" is called on buffer write in the autogroup above.
function! <SID>StripTrailingWhitespaces()
    " save last search & cursor position
    let _s=@/
    let l = line(".")
    let c = col(".")
    %s/\s\+$//e
    let @/=_s
    call cursor(l, c)
endfunction
" }}}

" vim:foldmethod=marker:foldlevel=0
