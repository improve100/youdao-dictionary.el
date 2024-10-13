;;; youdao-dictionary.el --- Youdao Dictionary interface for Emacs  -*- lexical-binding: t; -*-

;; Copyright © 2015-2017 Chunyang Xu

;; Author: Chunyang Xu <xuchunyang56@gmail.com>
;; URL: https://github.com/xuchunyang/youdao-dictionary.el
;; Package-Requires: ((popup "0.5.0") (pos-tip "0.4.6") (chinese-word-at-point "0.2") (names "0.5") (emacs "24"))
;; Version: 0.5.3
;; Created: 11 Jan 2015
;; Keywords: convenience, Chinese, dictionary

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; A simple Youdao Dictionary interface for Emacs
;;
;; Below are commands you can use:
;; `youdao-dictionary-search-at-point'
;; Search word at point and display result with buffer
;; `youdao-dictionary-search-at-point+'
;; Search word at point and display result with popup-tip
;; `youdao-dictionary-search-from-input'
;; Search word from input and display result with buffer
;; `youdao-dictionary-search-and-replace'
;; Search word at point and display result with popup-menu, replace word with
;; selected translation.
;; `youdao-dictionary-play-voice-at-point'
;; Play voice of word at point (by [[https://github.com/snyh][@snyh]])
;; `youdao-dictionary-play-voice-from-input'
;; Play voice of word from input (by [[https://github.com/snyh][@snyh]])
;; `youdao-dictionary-search-at-point-tooltip'
;; Search word at point and display result with pos-tip

;;; Code:
(require 'json)
(require 'url)
(require 'org)
(require 'chinese-word-at-point)
(require 'popup)
(require 'pos-tip)
(require 'auth-source)
(eval-when-compile (require 'names))

(declare-function pdf-view-active-region-text "pdf-view" ())
(declare-function pdf-view-active-region-p "pdf-view" ())
(declare-function posframe-delete "posframe")
(defvar url-http-response-status)

(defgroup youdao-dictionary nil
  "Youdao dictionary interface for Emacs."
  :prefix "youdao-dictionary-"
  :group 'tools
  :link '(url-link :tag "Github" "https://github.com/xuchunyang/youdao-dictionary.el"))

;; (define-namespace youdao-dictionary-

;;;###autoload
(defconst youdao-dictionary-api-url
  "http://fanyi.youdao.com/openapi.do?keyfrom=YouDaoCV&key=659600698&type=data&doctype=json&version=1.1&q=%s"
  "Youdao dictionary API template, URL `http://dict.youdao.com/'.")

(defconst youdao-dictionary-api-url-v3
  "https://openapi.youdao.com/api"
  "Youdao dictionary API template, URL `http://dict.youdao.com/'.")

(defconst youdao-dictionary-voice-url
  "http://dict.youdao.com/dictvoice?type=2&audio=%s"
  "Youdao dictionary API for query the voice of word.")

(defcustom youdao-dictionary-secret-key (getenv "YOUDAO_SECRET_KEY")
  "Youdao dictionary Secret Key. You can get it from ai.youdao.com."
  :type 'string)

(defcustom youdao-dictionary-app-key (getenv "YOUDAO_APP_KEY")
  "Youdao dictionary App Key. You can get it from ai.youdao.com."
  :type 'string)

(defconst youdao-dictionary-sign-type "v3"
  "Youdao dictionary sign type")

(defcustom youdao-dictionary-from "auto"
  "Source language. see http://ai.youdao.com/DOCSIRMA/html/%E8%87%AA%E7%84%B6%E8%AF%AD%E8%A8%80%E7%BF%BB%E8%AF%91/API%E6%96%87%E6%A1%A3/%E6%96%87%E6%9C%AC%E7%BF%BB%E8%AF%91%E6%9C%8D%E5%8A%A1/%E6%96%87%E6%9C%AC%E7%BF%BB%E8%AF%91%E6%9C%8D%E5%8A%A1-API%E6%96%87%E6%A1%A3.html"
  :type 'string)

(defcustom youdao-dictionary-to "auto"
  "dest language. see http://ai.youdao.com/DOCSIRMA/html/%E8%87%AA%E7%84%B6%E8%AF%AD%E8%A8%80%E7%BF%BB%E8%AF%91/API%E6%96%87%E6%A1%A3/%E6%96%87%E6%9C%AC%E7%BF%BB%E8%AF%91%E6%9C%8D%E5%8A%A1/%E6%96%87%E6%9C%AC%E7%BF%BB%E8%AF%91%E6%9C%8D%E5%8A%A1-API%E6%96%87%E6%A1%A3.html"
  :type 'string)

(defcustom youdao-dictionary-buffer-name "*Youdao Dictionary*"
  "Result Buffer name."
  :type 'string)

(defcustom youdao-dictionary-search-history-file nil
  "If non-nil, the file be used for saving searching history."
  :type '(choice (const :tag "Don't save history" nil)
                 (string :tag "File path")))

(defcustom youdao-dictionary-use-chinese-word-segmentation nil
  "If Non-nil, support Chinese word segmentation(中文分词).

See URL `https://github.com/xuchunyang/chinese-word-at-point.el' for more info."
  :type 'boolean)

(defface youdao-dictionary-posframe-tip-face
  '((t (:inherit tooltip)))
  "Face for posframe tip."
  :group 'youdao-dictionary)

(defun youdao-dictionary-secret-key ()
  (or youdao-dictionary-secret-key
      (let ((plist (car (auth-source-search :host "openapi.youdao.com" :max 1))))
        (and plist (funcall (plist-get plist :secret))))))

(defun youdao-dictionary-app-key ()
  (or youdao-dictionary-app-key
      (let ((plist (car (auth-source-search :host "openapi.youdao.com" :max 1))))
        (plist-get plist :user))))

(defun youdao-dictionary-get-salt ()
  (number-to-string (random 1000)))

(defun youdao-dictionary-get-curtime ()
  (format-time-string "%s"))

(defun youdao-dictionary-get-input (word)
  (let ((len (length word)))
    (if (> len 20)
        (concat (substring word 0 10)
                (number-to-string len)
                (substring word -10))
      word)))

(defun youdao-dictionary-get-sign (salt curtime word)
  (let* ((input (youdao-dictionary-get-input word))
         (signstr (concat (youdao-dictionary-app-key) input salt curtime (youdao-dictionary-secret-key))))
    (secure-hash 'sha256 signstr)))

(defun youdao-dictionary--format-voice-url (query-word)
  "Format QUERY-WORD as voice url."
  (format youdao-dictionary-voice-url (url-hexify-string query-word)))

(defun youdao-dictionary--request-v3-p ()
  (if (and (youdao-dictionary-app-key) (youdao-dictionary-secret-key))
      t
    (user-error "You have not set the API key/secret.  See also URL `https://github.com/xuchunyang/youdao-dictionary.el#usage'.")))

(defun youdao-dictionary--format-request-url (query-word)
  "Format QUERY-WORD as a HTTP request URL."
  (if (youdao-dictionary--request-v3-p)
      youdao-dictionary-api-url-v3
    (format youdao-dictionary-api-url (url-hexify-string query-word))))

(defun youdao-dictionary--parse-response ()
  "Parse response as JSON."
  (set-buffer-multibyte t)
  (goto-char (point-min))
  (when (/= 200 url-http-response-status)
    (error "Problem connecting to the server"))
  (re-search-forward "^$" nil 'move)
  (prog1 (json-read)
    (kill-buffer (current-buffer))))

(defun youdao-dictionary--request (word &optional callback)
  "Request WORD, return JSON as an alist if successes."
  (when (and youdao-dictionary-search-history-file (file-writable-p youdao-dictionary-search-history-file))
    ;; Save searching history
    (append-to-file (concat word "\n") nil youdao-dictionary-search-history-file))
  (let* ((salt (youdao-dictionary-get-salt))
         (curtime (youdao-dictionary-get-curtime))
         (sign (youdao-dictionary-get-sign salt curtime word))
         (url-request-data (when (youdao-dictionary--request-v3-p)
                             (mapconcat #'identity (list (concat "q=" (url-hexify-string word))
                                                (concat "from=" youdao-dictionary-from)
                                                (concat "to=" youdao-dictionary-to)
                                                (concat "appKey=" (youdao-dictionary-app-key))
                                                (concat "salt=" salt)
                                                (concat "sign=" (url-hexify-string sign))
                                                (concat "signType=" youdao-dictionary-sign-type)
                                                (concat "curtime=" curtime))
                                          "&" )))
         (url-request-method (when (youdao-dictionary--request-v3-p)
                               "POST"))
         (url-request-extra-headers (when (youdao-dictionary--request-v3-p)
                                      '(("Content-Type" . "application/x-www-form-urlencoded")))))
    (if callback
        (url-retrieve (youdao-dictionary--format-request-url word) callback)
      (with-current-buffer (url-retrieve-synchronously (youdao-dictionary--format-request-url word))
        (youdao-dictionary--parse-response)))))

(defun youdao-dictionary--explains (json)
  "Return explains as a vector extracted from JSON."
  (cdr (assoc 'explains (cdr (assoc 'basic json)))))

(defun youdao-dictionary--prompt-input ()
  "Prompt input object for translate."
  (let ((current-word (youdao-dictionary--region-or-word)))
    (read-string (format "Word (%s): "
                         (or current-word ""))
                 nil nil
                 current-word)))

(defun youdao-dictionary--strip-explain (explain)
  "Remove unneed info in EXPLAIN for replace.

i.e. `[语][计] dictionary' => 'dictionary'."
  (replace-regexp-in-string "^[[].* " "" explain))

(defun youdao-dictionary--region-or-word ()
  "Return word in region or word at point."
  (if (derived-mode-p 'pdf-view-mode)
      (if (pdf-view-active-region-p)
          (mapconcat 'identity (pdf-view-active-region-text) "\n"))
    (if (use-region-p)
        (buffer-substring-no-properties (region-beginning)
                                        (region-end))
      (thing-at-point (if youdao-dictionary-use-chinese-word-segmentation
                          'chinese-or-other-word
                        'word)
                      t))))

(defun youdao-dictionary--format-result (json)
  "Format result in JSON."
  (let* ((query        (assoc-default 'query       json)) ; string
         (translation  (assoc-default 'translation json)) ; array
         (_errorCode    (assoc-default 'errorCode   json)) ; number
         (web          (assoc-default 'web         json)) ; array
         (basic        (assoc-default 'basic       json)) ; alist
         ;; construct data for display
         (phonetic (assoc-default 'phonetic basic))
         (translation-str (mapconcat
                           (lambda (trans) (concat "- " trans))
                           translation "\n"))
         (basic-explains-str (mapconcat
                              (lambda (explain) (concat "- " explain))
                              (assoc-default 'explains basic) "\n"))
         (web-str (mapconcat
                   (lambda (k-v)
                     (format "- %s :: %s"
                             (assoc-default 'key k-v)
                             (mapconcat 'identity (assoc-default 'value k-v) "; ")))
                   web "\n")))
    (if basic
        (format "%s [%s]\n\n* Basic Explains\n%s\n\n* Web References\n%s\n"
                query phonetic basic-explains-str web-str)
      (format "%s\n\n* Translation\n%s\n"
              query translation-str))))

(defun youdao-dictionary--pos-tip (string)
  "Show STRING using pos-tip-show."
  (pos-tip-show string nil nil nil 0)
  (unwind-protect
      (push (read-event) unread-command-events)
    (pos-tip-hide)))

(defvar youdao-dictionary-current-buffer-word nil)

(defun youdao-dictionary--posframe-tip (string)
  "Show STRING using posframe-show."
  (unless (and (require 'posframe nil t) (posframe-workable-p))
    (error "Posframe not workable"))

  (let ((word (youdao-dictionary--region-or-word)))
    (if word
        (progn
          (with-current-buffer (get-buffer-create youdao-dictionary-buffer-name)
            (let ((inhibit-read-only t))
              (erase-buffer)
              (mode)
              (insert string)
              (goto-char (point-min))
              (set (make-local-variable 'youdao-dictionary-current-buffer-word) word)))
          (posframe-show youdao-dictionary-buffer-name
                         :left-fringe 8
                         :right-fringe 8
                         :internal-border-color (face-foreground 'default)
                         :internal-border-width 1)
          (unwind-protect
              (push (read-event) unread-command-events)
            (progn
              (posframe-delete youdao-dictionary-buffer-name)
              (other-frame 0))))
      (message "Nothing to look up"))))

(defun youdao-dictionary-play-voice-of-current-word ()
  "Play voice of current word shown in *Youdao Dictionary*."
  (interactive)
  (if (local-variable-if-set-p 'youdao-dictionary-current-buffer-word)
      (youdao-dictionary--play-voice youdao-dictionary-current-buffer-word)))

(define-derived-mode mode org-mode "Youdao-dictionary"
  "Major mode for viewing Youdao dictionary result.
\\{youdao-dictionary-mode-map}"
  (read-only-mode 1)
  (define-key mode-map "q" 'quit-window)
  (define-key mode-map "p" 'youdao-dictionary-play-voice-of-current-word)
  (define-key mode-map "y" 'youdao-dictionary-play-voice-at-point))

(defun youdao-dictionary--search-and-show-in-buffer-subr (word content)
  (with-current-buffer (get-buffer-create youdao-dictionary-buffer-name)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (mode)
      (insert content)
      (goto-char (point-min))
      (set (make-local-variable 'youdao-dictionary-current-buffer-word) word))
    (unless (get-buffer-window (current-buffer))
      (switch-to-buffer-other-window youdao-dictionary-buffer-name))))

(defun youdao-dictionary--search-and-show-in-buffer (word &optional async)
  "Search WORD and show result in `youdao-dictionary-buffer-name' buffer."
  (unless word
    (user-error "Nothing to look up"))
  (if async
      (youdao-dictionary--request word (lambda (_status)
                       (youdao-dictionary--search-and-show-in-buffer-subr
                        word
                        (youdao-dictionary--format-result (youdao-dictionary--parse-response)))))
    (youdao-dictionary--search-and-show-in-buffer-subr word (youdao-dictionary--format-result (youdao-dictionary--request word)))))

:autoload
(defun youdao-dictionary-search-at-point ()
  "Search word at point and display result with buffer."
  (interactive)
  (let ((word (youdao-dictionary--region-or-word)))
    (youdao-dictionary--search-and-show-in-buffer word)))

(defun youdao-dictionary-search-at-point- (func)
  "Search word at point and display result with given FUNC."
  (let ((word (youdao-dictionary--region-or-word)))
    (if word
        (funcall func (youdao-dictionary--format-result (youdao-dictionary--request word)))
      (message "Nothing to look up"))))

:autoload
(defun youdao-dictionary-search-at-point+ ()
  "Search word at point and display result with popup-tip."
  (interactive)
  (youdao-dictionary-search-at-point- #'popup-tip))

:autoload
(defun youdao-dictionary-search-at-point-posframe ()
  "Search word at point and display result with posframe."
  (interactive)
  (youdao-dictionary-search-at-point- #'youdao-dictionary--posframe-tip))

:autoload
(defun youdao-dictionary-search-at-point-tooltip ()
  "Search word at point and display result with pos-tip."
  (interactive)
  (youdao-dictionary-search-at-point- #'youdao-dictionary--pos-tip))

:autoload
(defun youdao-dictionary-search-from-input ()
  "Search word from input and display result with buffer."
  (interactive)
  (let ((word (youdao-dictionary--prompt-input)))
    (youdao-dictionary--search-and-show-in-buffer word)))

:autoload
(defun youdao-dictionary-search-and-replace ()
  "Search word at point and replace this word with popup menu."
  (interactive)
  (if (use-region-p)
      (let ((region-beginning (region-beginning)) (region-end (region-end))
            (selected (popup-menu* (mapcar #'youdao-dictionary--strip-explain
                                           (append (youdao-dictionary--explains
                                                    (youdao-dictionary--request
                                                     (youdao-dictionary--region-or-word)))
                                                   nil)))))
        (when selected
          (insert selected)
          (kill-region region-beginning region-end)))
    ;; No active region
    (let* ((bounds (bounds-of-thing-at-point (if youdao-dictionary-use-chinese-word-segmentation
                                                 'chinese-or-other-word
                                               'word)))
           (beginning-of-word (car bounds))
           (end-of-word (cdr bounds)))
      (when bounds
        (let ((selected
               (popup-menu* (mapcar
                             #'youdao-dictionary--strip-explain
                             (append (youdao-dictionary--explains
                                      (youdao-dictionary--request
                                       (thing-at-point
                                        (if youdao-dictionary-use-chinese-word-segmentation
                                            'chinese-or-other-word
                                          'word))))
                                     nil)))))
          (when selected
            (insert selected)
            (kill-region beginning-of-word end-of-word)))))))

(defvar youdao-dictionary-history nil)

:autoload
(defun youdao-dictionary-search (query)
  "Show the explanation of QUERY from Youdao dictionary."
  (interactive
   (let* ((string (or (if (use-region-p)
                          (buffer-substring
                           (region-beginning) (region-end))
                        (thing-at-point 'word))
                      (read-string "Search Youdao Dictionary: " nil 'youdao-dictionary-history))))
     (list string)))
  (youdao-dictionary--search-and-show-in-buffer query))

:autoload
(defun youdao-dictionary-search-async (query)
  "Show the explanation of QUERY from Youdao dictionary asynchronously."
  (interactive
   (let* ((string (or (if (use-region-p)
                          (buffer-substring
                           (region-beginning) (region-end))
                        (thing-at-point 'word))
                      (read-string "Search Youdao Dictionary: " nil 'youdao-dictionary-history))))
     (list string)))
  (youdao-dictionary--search-and-show-in-buffer query 'async))

(defun youdao-dictionary--play-voice (word)
  "Play voice of the WORD if there has mplayer or mpg123 program."
  (let ((player (or (executable-find "mpv")
                    (executable-find "mplayer")
                    (executable-find "mpg123"))))
    (if player
        (start-process player nil player (youdao-dictionary--format-voice-url word))
      (user-error "mplayer or mpg123 is needed to play word voice"))))

:autoload
(defun youdao-dictionary-play-voice-at-point ()
  "Play voice of the word at point."
  (interactive)
  (let ((word (youdao-dictionary--region-or-word)))
    (youdao-dictionary--play-voice word)))

:autoload
(defun youdao-dictionary-play-voice-from-input ()
  "Play voice of user input word."
  (interactive)
  (let ((word (youdao-dictionary--prompt-input)))
    (youdao-dictionary--play-voice word)))


;; )


(provide 'youdao-dictionary)

;; Local Variables:
;; coding: utf-8
;; indent-tabs-mode: nil
;; End:

;;; youdao-dictionary.el ends here
