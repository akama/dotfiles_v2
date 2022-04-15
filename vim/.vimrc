" KEYBINDINGS {{{
" Change leader to space
let mapleader = "\<Space>"
" Open nerdtree with leader-e
map <leader>e :NERDTreeToggle<CR>
" Open undotree with leader-u
map <leader>u :UndotreeToggle<CR>
" }}}

" UNDO {{{
set undodir=~/.vim/undodir
set undofile
set undolevels=1000 "maximum number of changes that can be undone
set undoreload=10000 "maximum number lines to save for undo on a buffer reload
" }}}


" GENERAL SETTINGS {{{

" Turn on syntax processing
syntax on

" set default encoding
set encoding=utf-8

" turn on line numbers
set number

" Highlight matching parentheses/races/brackets
set showmatch

" Ignore files in wildcard search.
set wildignore+=*/tmp/*,*.so,*.swp,*.zip,*/_build/*,*/_opam/*

" Make backspace work normally.
set backspace=indent,eol,start

" Set colorscheme to nord
colorscheme nord
" }}}

" FZF {{{
" Add fzf ff installed using Homebrew
set rtp+=/usr/local/opt/fzf
" Turn off highlights in ale
let g:ale_set_highlights = 0
" }}}

" ALE {{{
let g:ale_set_balloons = 1
" }}}

" TABS & SPACES {{{
" set the visual spaces per tab
set tabstop=2
" number of spaces in tab when editing
set softtabstop=2
set shiftwidth=2
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
" }}}

" FOLDING {{{
" enable folding
set foldenable
" open most folds by default
set foldlevelstart=0
" fold based on indent level
set foldmethod=indent
" }}}

" OCAML {{{
let g:opamshare = substitute(system('opam config var share'),'\n$','','''')
execute "set rtp+=" . g:opamshare . "/merlin/vim"
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

" Load all plugins now.
" Plugins need to be added to runtimepath before helptags can be generated.
packloadall
" Load all of the helptags now, after plugins have been loaded.
" All messages and errors will be ignored.
silent! helptags ALL

" vim:foldmethod=marker:foldlevel=0
