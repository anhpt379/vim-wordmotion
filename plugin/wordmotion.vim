if exists('g:loaded_wordmotion')
	finish
endif
let g:loaded_wordmotion = 1

let s:prefix = get(g:, 'wordmotion_prefix', '')
let s:mappings = get(g:, 'wordmotion_mappings', { })
let s:spaces = get(g:, 'wordmotion_spaces', '_')

let s:flags = { 'w' : '', 'e' : 'e', 'b' : 'b', 'ge' : 'be' }

if exists('s:existing') " {{{
	for s:mapping in s:existing
		let s:mode = s:mapping['mode']
		let s:unmap = s:mode . 'unmap'
		let s:lhs = s:mapping['lhs']
		let s:rhs = s:mapping['rhs']
		if hasmapto(s:rhs, s:mode)
			execute s:unmap s:lhs
		endif
	endfor
endif " }}}
let s:existing = []

for s:motion in [ 'w', 'e', 'b', 'ge' ] " {{{
	if !has_key(s:mappings, s:motion)
		let s:mappings[s:motion] = s:prefix . s:motion
	elseif empty(s:mappings[s:motion])
		continue
	endif
	for s:mode in [ 'n', 'x', 'o' ]
		let s:map = s:mode . 'noremap'
		let s:lhs = s:mappings[s:motion]
		let s:m = "'" . s:mode . "'"
		let s:f = "'" . s:flags[s:motion] . "'"
		let s:args = join([ 'v:count1', s:m, s:f, '[]' ], ', ')
		let s:rhs = ':<C-U>call <SID>WordMotion(' . s:args . ')<CR>'
		execute s:map '<silent>' . s:lhs s:rhs
		call add(s:existing, { 'mode' : s:mode, 'lhs' : s:lhs, 'rhs' : s:rhs })
	endfor
endfor " }}}

let s:inner = { 'aw' : 0, 'iw' : 1 }

let s:motion = 'w'
for s:qualifier in [ 'a', 'i' ] " {{{
	let s:qualified_motion = s:qualifier . s:motion
	if !has_key(s:mappings, s:qualified_motion)
		let s:mappings[s:qualified_motion] = s:qualifier . s:prefix . s:motion
	elseif empty(s:mappings[s:qualified_motion])
		continue
	endif
	for s:mode in [ 'x', 'o' ]
		let s:map = s:mode . 'noremap'
		let s:lhs = s:mappings[s:qualified_motion]
		let s:m = "'" . s:mode . "'"
		let s:i = s:inner[s:qualified_motion]
		let s:args = join([ 'v:count1', s:m, s:i ], ', ')
		let s:rhs = ':<C-U>call <SID>AOrInnerWordMotion(' . s:args . ')<CR>'
		execute s:map '<silent>' . s:lhs s:rhs
		call add(s:existing, { 'mode' : s:mode, 'lhs' : s:lhs, 'rhs' : s:rhs })
	endfor
endfor " }}}

let s:crcw = '<C-R><C-W>'
if !has_key(s:mappings, s:crcw)
	let s:mappings[s:crcw] = s:crcw
endif
if !empty(s:mappings[s:crcw])
	let s:mode = 'c'
	let s:map = s:mode . 'noremap'
	let s:lhs = '<expr>' . s:mappings[s:crcw]
	let s:rhs = '<SID>GetCurrentWord()'
	execute s:map s:lhs s:rhs
	call add(s:existing, { 'mode' : s:mode, 'lhs' : s:lhs, 'rhs' : s:rhs })
endif

" '-' in the middle will turn into a range, move it to the back.
let s:spaces = substitute(s:spaces, '-\(.*\)$', '\1-', '')
let s:s = '[[:space:]' . s:spaces . ']'
let s:S = '[^[:space:]' . s:spaces . ']'

function! s:BuildWordPattern() abort " {{{
	" [:alnum:] and [:alpha:] are ASCII only
	let l:a = '[[:digit:][:lower:][:upper:]]'
	let l:d = '[[:digit:]]'
	let l:p = '[[:print:]]'
	let l:l = '[[:lower:]]'
	let l:u = '[[:upper:]]'
	let l:x = '[[:xdigit:]]'

	" set complement
	function! s:C(set, ...) abort " {{{
		let l:exclude = join(map(copy(a:000), 'v:val[1:-2]'), '')
		return '\%(\%([' . l:exclude . ']\)\@!' . a:set . '\)'
	endfunction " }}}

	let l:words = get(g:, 'wordmotion_extra', [])
	call add(l:words, l:u . l:l . '\+')          " CamelCase
	call add(l:words, l:u . '\+\ze' . l:u . l:l) " ACRONYMSBeforeCamelCase
	call add(l:words, l:u . '\+')                " UPPERCASE
	call add(l:words, l:l . '\+')                " lowercase
	call add(l:words, '0[xX]' . l:x . '\+')      " 0x00 0Xff
	call add(l:words, '0[oO][0-7]\+')            " 0o00 0O77
	call add(l:words, '0[bB][01]\+')             " 0b00 0B11
	call add(l:words, '#[0-9a-fA-F]\{6}')        " #aa00ff #AA00FF
	call add(l:words, '#[0-9a-fA-F]\{3}')        " #a0f #A0F
	call add(l:words, l:d . '\+')                " 1234 5678
	call add(l:words, s:C(l:p, l:a, s:s) . '\+') " other printable characters
	call add(l:words, '\%^')                     " start of file
	call add(l:words, '\%$')                     " end of file
	return join(l:words, '\|')
endfunction " }}}

let s:word = s:BuildWordPattern()

function! <SID>WordMotion(count, mode, flags, extra) abort " {{{
	if a:mode == 'x'
		normal! gv
	elseif a:mode == 'o' && a:flags =~# 'e'
		" need to make this inclusive for operator pending mode
		normal! v
	endif

	let l:words = a:extra + [s:word]
	if a:flags != 'e' " e does not stop in an empty line
		call add(l:words, '^$')
	endif

	let l:pattern = '\m\%(' . join(l:words, '\|') . '\)'

	" save position to see if it moved
	let l:pos = getpos('.')

	for @_ in range(a:count)
		call search(l:pattern, a:flags . 'W')
	endfor

	" ugly hack for 'w' going forwards at end of file
	" and 'ge' going backwards at beginning of file
	if a:count && l:pos == getpos('.')
		" cursor didn't move
		if a:flags == 'be' && line('.') == 1
			" at first line and going backwards, let's go to the front
			normal! 0
		elseif a:flags == '' && line('.') == line('$')
			" at last line and going forwards, let's go to the back
			if a:mode == 'o'
				" need to include last character if in operator pending mode
				normal! v
			endif
			normal! $
		endif
	endif
endfunction " }}}

function! <SID>AOrInnerWordMotion(count, mode, inner) abort " {{{
	let l:flags = 'e'
	let l:extra = []
	let l:backwards = 0
	let l:count = a:count
	let l:existing_selection = 0

	if a:mode == 'x'
		normal! gv
		if getpos("'<") == getpos("'>")
			" no existing selection, exit visual mode
			execute 'normal!' visualmode()
		else
			let l:existing_selection = 1
			let l:start = getpos('.')
			if l:start == getpos("'<")
				let l:flags = 'b'
				let l:backwards = 1
			endif
		endif
	endif

	if a:inner
		" for inner word, count white spaces too
		call add(l:extra, s:s . '\+')
	else
		if getline('.')[col('.') - 1] =~ s:s
			if !l:existing_selection
				let l:backwards = 1
			endif
			call search('\m' . s:S, 'W')
		endif
	endif

	if !l:existing_selection
		call <SID>WordMotion(1, 'n', 'bc', l:extra)
		let l:start = getpos('.')
		normal! v
		call <SID>WordMotion(1, 'n', 'ec', l:extra)
		let l:count -= 1
	endif

	call <SID>WordMotion(l:count, 'n', l:flags, l:extra)

	if !a:inner
		if col('.') == col('$') - 1
			" at end of line, go back, and consume preceding white spaces
			let l:backwards = 1
		endif

		if l:backwards && !l:existing_selection
			" selection is forwards, but need to extend backwards
			let l:end = getpos('.')
			call cursor(l:start[1], l:start[2])
			call search('\m' . s:s . '\+\%#', 'bW')
			normal! vv
			call cursor(l:end[1], l:end[2])
		elseif l:backwards
			" selection is actually going backwards
			call search('\m' . s:s . '\+\%#', 'bW')
		else
			" forward selection, consume following white spaces
			call search('\m\%#.' . s:s . '\+', 'eW')
		endif
	endif
endfunction " }}}

function! <SID>GetCurrentWord() abort " {{{
	let l:cursor = getpos('.')
	call <SID>WordMotion(1, 'n', 'ec', [])
	let l:end = getpos('.')
	call <SID>WordMotion(1, 'n', 'bc', [])
	let l:start = getpos('.')
	call cursor(l:cursor)
	let l:line = l:cursor[1]
	if l:start[1] != l:line || l:end[1] != l:line ||
				\ len(getline(l:line)) < l:end[2] ||
				\ getline(l:line)[l:end[2]-1] =~ s:s
		echohl ErrorMsg
		echomsg 'E348: No string under cursor'
		echohl None
		return ''
	else
		return getline(l:line)[l:start[2]-1:l:end[2]-1]
	endif
endfunction " }}}

" vim:fdm=marker
