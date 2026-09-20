;; Injections for the Grammar for GCC Machine Description Language.
;; Copyright (C) 2026 Pietro Monteiro <pietro@sociotechnical.xyz>.
;;
;; This file is part of tree-sitter-gcc-md, a Tree-sitter grammar for
;; the GCC Machine Description Language.
;;
;; tree-sitter-gcc-md is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.
;;
;; tree-sitter-gcc-md is distributed in the hope that it will be
;; useful, but WITHOUT ANY WARRANTY; without even the implied warranty
;; of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with tree-sitter-gcc-md. If not, see
;; <https://www.gnu.org/licenses/>.

;; Use the cpp grammar to parse C++ blocks.
((cpp) @injection.content
 (#set! injection.language "cpp"))
