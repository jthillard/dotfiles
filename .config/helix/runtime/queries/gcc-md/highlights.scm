;; Highlights for the Grammar for GCC Machine Description Language.
;; Copyright (C) 2026 Pietro Monteiro <pietro@sociotechnical.xyz>.
;; Copyright (C) 2026 Julien Thillard <julien.thillard38@gmail.com>.
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

(comment) @comment

(ident) @keyword

(number) @constant

[(string) (string_plain)] @string

(string (string_escape) @constant.character.escape)
(string_plain (string_escape) @constant.character.escape)

(ident_with_mode mode: (ident) @type)

[
 ":"
 ] @punctuation.delimiter

[
 "("
 ")"
 "["
 "]"
 "{"
 "}"
 ] @punctuation.bracket

(string (string_template) @type)

(string (string_template ["<" ">"] @punctuation.delimiter))
