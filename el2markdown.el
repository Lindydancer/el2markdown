;;; el2markdown.el -- Convert commentary section of elisp files to markdown.

;; Copyright (C) 2013-2014 Anders Lindgren

;; Author: Anders Lindgren
;; Version: 0.0.1
;; Created: 2013-03-26
;; URL: https://github.com/Lindydancer/el2markdown

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package converts *Commentary* section in Emacs Lisp modules to
;; text files in MarkDown format, a format supporting headings, code
;; blocks, basic text styles, bullet lists etc.
;;
;; The MarkDown is used by many web sites as an alternative to plain
;; texts. For example, it is used by sites like StackOverflow and
;; GitHub.

;; What is converted:
;;
;; Everything between the `Commentary:' and `Code:' markers are
;; included in the generated text. In addition, the title and *some*
;; metadata are also included.

;; How to write comments:
;;
;; The general rule of thumb is that the Emacs Lisp module should be
;; written using plain text, as they always have been written.
;;
;; However, some things are recognized. A single line ending with a
;; colon is cosidered a *heading*. If this line is at the start of a
;; comment block, it is considered a main (level 2) heading. Otherwise
;; it is considered a (level 3) subheading. Note that the line
;; precedes a bullet list or code, it will not be treated as a
;; subheading.
;;
;; Use Markdown formatting:
;;
;; It is possible to use markdown syntax in the text, like *this*, and
;; **this**.
;;
;; Conventions:
;;
;; The following conventions are used when converting elisp comments
;; to MarkDown:
;;
;; * Code blocks using either the Markdown convention by indenting the
;;   block with four extra spaces, or by starting a paragraph with a
;;   `('.
;;
;; * In elisp comments, a reference to `code' (backquote - quote),
;;   they will be converted to MarkDown style (backquote - backquote).
;;
;; * In elisp comments, bullets in lists are typically separated by
;;   empty lines. In the converted text, the empty lines are removed,
;;   as required by MarkDown.
;;

;; Example:
;;
;;
;;     ;; This is a heading:
;;     ;;
;;     ;; Bla bla bla ...
;;
;;     ;; This is another heading:
;;     ;;
;;     ;; This is a pararaph!
;;     ;;
;;     ;; A subheading:
;;     ;;
;;     ;; Another paragraph.
;;     ;;
;;     ;; This line is *not* as a subheading:
;;     ;;
;;     ;; * A bullet in a list
;;     ;;
;;     ;; * Another bullet.

;; Installation:
;;
;; Place this package somewhere in Emacs `load-path' and add the
;; following lines to a suitable init file:
;;
;; (autoload 'el2markdown-view-buffer  nil t)
;; (autoload 'el2markdown-write-file   nil t)
;; (autoload 'el2markdown-write-readme nil t)

;; Usage:
;;
;; To generate the markdown representation of the current buffer to a
;; temporary buffer, use:
;;
;;     M-x el2markdown-view-buffer RET
;;
;; To write the markdown representation of the current buffer to a
;; file, use:
;;
;;     M-x el2markdown-write-file RET name-of-file RET
;;
;; In sites like GitHub, if a file named README.md exists in the root
;; directory of an archive, it is displayed when viewing the archive.
;; To generate a README.md file, in the same directory as the current
;; buffer, use:
;;
;;     M-x el2markdown-write-readme RET
;;
;; Batch mode:
;;
;; You can run el2markdown in batch mode. The function
;; `el2markdown-write-readme' can be called directly using the `-f'
;; option. The others can be accessed with the `--eval' form.
;;
;; For example,
;;
;;     emacs -batch -l el2markdown.el my-file.el -f el2markdown-write-readme
;;

;;; Code:

(defvar el2markdown-empty-comment "^;; *\\(\\({{{\\|}}}\\).*\\)?$"
  "Regexp of lines that should be considered empty.")

(defun el2markdown-view-buffer ()
  "Convert comment section to markdown and display in temporary buffer."
  (interactive)
  (with-output-to-temp-buffer "*el2markup*"
    (el2markdown-convert)))


(defun el2markdown-write-file (&optional file-name overwrite-without-confirm)
  "Convert comment section to markdown and write to file."
  (interactive
   (let ((suggested-name (and (buffer-file-name)
                              (concat (file-name-sans-extension
                                       (buffer-file-name))
                                      ".md"))))
     (list (read-file-name "Write markdown file: "
                           default-directory
                           suggested-name
                           nil
                           (file-name-nondirectory suggested-name)))))
  (unless file-name
    (setq file-name (concat (buffer-file-name) ".md")))
  (let ((buffer (current-buffer))
        (orig-buffer-file-coding-system buffer-file-coding-system))
    (with-temp-buffer
      ;; Inherit the file coding from the buffer being converted.
      (setq buffer-file-coding-system orig-buffer-file-coding-system)
      (let ((standard-output (current-buffer)))
        (with-current-buffer buffer
          (el2markdown-convert))
        ;; Note: Must set `require-final-newline' inside
        ;; `with-temp-buffer', otherwise the value will be overridden by
        ;; the buffers local value.
        (let ((require-final-newline nil))
          (write-file file-name (not overwrite-without-confirm)))))))


(defun el2markdown-write-readme ()
  "Generate README.md, designed to be used in batch mode."
  (interactive)
  (el2markdown-write-file "README.md" noninteractive))


(defun el2markdown-convert ()
  (save-excursion
    (goto-char (point-min))
    (el2markdown-convert-title)
    (el2markdown-convert-formal-information)
    (el2markdown-skip-to-commentary)
    (while
        (el2markdown-convert-section))
    (terpri)
    (princ "---")
    (terpri)
    (let ((file-name (buffer-file-name))
          (from ""))
      (if file-name
          (setq from (concat " from `"
                             (file-name-nondirectory file-name)
                             "`")))
      (princ (concat
              "Converted" from
              " by "
              "[*el2markup*](https://github.com/Lindydancer/el2markdown)."))
      (terpri))))


(defun el2markdown-skip-empty-lines()
  (while (and (bolp) (eolp) (not (eobp)))
    (forward-line)))


(defun el2markdown-translate-string (string)
  (let ((res ""))
    (while (string-match "`\\([^']*\\)'" string)
      (setq res (concat res (substring string 0 (match-beginning 0))))
      (let ((content (match-string 1 string))
            (beg "`")
            (end "`"))
        (setq string (substring string (match-end 0)))
        (when (save-match-data
                (let ((case-fold-search nil))
                  (string-match "^[CM]-" content)))
          (setq beg "<kbd>")
          (setq end "</kbd>"))
        (setq res (concat res beg content end))))
    (concat res string)))


(defun el2markdown-convert-title ()
  (when (looking-at ";;+ \\(.*\\)\\.el -- \\(.*\\)$")
    (el2markdown-emit-header 1 (concat (match-string-no-properties 1)
                                       " - "
                                       (match-string-no-properties 2)))
    (forward-line)))


(defun el2markdown-convert-formal-information ()
  (save-excursion
    (goto-char (point-min))
    (let ((limit (save-excursion
                   (re-search-forward "^;;; Commentary:$" nil t))))
      (when limit
        (el2markdown-convert-formal-information-item "Author"  limit)
        (el2markdown-convert-formal-information-item "Version" limit)
        (el2markdown-convert-formal-information-item "URL"     limit 'link)
        (terpri)))))


(defun el2markdown-convert-formal-information-item (item lim &optional link)
  (when (re-search-forward (concat "^;; " item ": *\\(.*\\)") nil t)
    (let ((s (match-string-no-properties 1)))
      (if link
          (setq s (concat "[" s "](" s ")")))
      (princ (concat "*" item ":* " s "<br>"))
      (terpri))))


(defun el2markdown-skip-to-commentary ()
  (if (re-search-forward ";;; Commentary:$" nil t)
      (forward-line)))


(defun el2markdown-convert-section ()
  (el2markdown-skip-empty-lines)
  (if (or (looking-at  "^;;; Code:$")
          (eobp))
      nil
    (let ((p (point)))
      (el2markdown-emit-rest-of-comment)
      (not (eq p (point))))))


(defun el2markdown-emit-header (count title)
  (princ (make-string count ?#))
  (princ " ")
  ;; Strip trailing ".".
  (let ((len nil))
    (while (progn
             (setq len (length title))
             (and (not (equal len 0))
                  (eq (elt title (- len 1)) ?.)))
      (setq title (substring title 0 (- len 1)))))
  (princ (el2markdown-translate-string title))
  (terpri)
  (terpri))


(defun el2markdown-is-at-bullet-list ()
  (save-excursion
    (while (looking-at "^;;$")
      (forward-line))
    (looking-at ";; *[-*]")))

(defun el2markdown-emit-rest-of-comment ()
  (let ((first t))
    (while (looking-at "^;;")
      ;; Skip empty lines.
      (while (looking-at el2markdown-empty-comment)
        (forward-line))
      (if (and (looking-at ";; \\(.*\\):$")
               (save-excursion
                 (save-match-data
                   (forward-line)
                   (looking-at el2markdown-empty-comment)))
               ;; When preceding code or bullet list, don't treat as
               ;; sub-header.
               (or first
                   (not (save-excursion
                          (save-match-data
                            (forward-line)
                            (while (looking-at el2markdown-empty-comment)
                              (forward-line))
                            (or (el2markdown-is-at-bullet-list)
                                (looking-at ";; *(")
                                (looking-at ";;     ")))))))
          ;; Header
          (progn
            (el2markdown-emit-header (if first 2 3)
                                     (match-string-no-properties 1))
            (forward-line 2)
            (setq first nil))
        ;; Section of text. (Things starting with a parenthesis is
        ;; assumes to be code.)
        (let ((is-code (looking-at ";; *("))
              (is-bullet (el2markdown-is-at-bullet-list)))
          (while (looking-at ";; ?\\(.+\\)$")
            (if is-code
                (princ "    "))
            (princ (el2markdown-translate-string
                    (match-string-no-properties 1)))
            (terpri)
            (forward-line))
          ;; Insert empty line between sections of code (unless
          ;; between bullet lists.)
          (if (and is-bullet
                   (el2markdown-is-at-bullet-list))
              nil
            (terpri)))))))

;; el2markdown.el ends here.
