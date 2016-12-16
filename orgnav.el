;;; orgnav.el --- Org tree navigation using helm

;; Copyright (C) 2016 Tal Wrii

;; Author: Tal Wrii (talwrii@gmail.com)
;; URL: github.com/talwrii/orgnav

;; Version: 0.1.0
;; Package-Version: 20161028.1
;; Package-Requires: ((helm "1.5.5") (dash) (s))
;; Created October 2016

;; Keywords: org tree navigation

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
;; See README.md

;;; Code:

(require 'helm)
(require 'helm-org)
(require 's)
(require 'dash)
(require 'cl-seq)

(defvar orgnav-log nil "Whether orgnav should log.")
(defvar orgnav-refile-depth 2 "The number of levels to show when refiling.")
(defvar orgnav-clock-depth 2 "The number of levels to show when clocking in.")
(defvar orgnav-clock-buffer nil "The buffer to search when clocking in.")

(defvar orgnav-mapping
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    ;; We can't call these things directly because we need
    ;; to quit helm

    ;; We should probably put a layer of naming
    ;; on top of this, so we don't refer to things
    ;; by index
    (define-key map (kbd "M-h") (lambda () (interactive) (helm-exit-and-execute-action 'orgnav--decrease-depth-action)))
    (define-key map (kbd "M-l") (lambda () (interactive) (helm-exit-and-execute-action 'orgnav--increase-depth-action)))
    (define-key map (kbd "M-.") (lambda () (interactive) (helm-exit-and-execute-action 'orgnav--explore-action)))
    (define-key map (kbd "M-,") (lambda () (interactive) (helm-exit-and-execute-action 'orgnav--explore-parent-action)))
    (define-key map (kbd "M-r") (lambda () (interactive) (helm-exit-and-execute-action 'orgnav--rename-action)))
    (define-key map (kbd "M-g") (lambda () (interactive) (helm-exit-and-execute-action 'orgnav--goto-action)))
    (define-key map (kbd "M-c") (lambda () (interactive) (helm-exit-and-execute-action 'orgnav--clock-action)))
    (define-key map (kbd "M-a") (lambda () (interactive) (helm-exit-and-execute-action 'orgnav--explore-ancestors-action)))
    (define-key map (kbd "M-n") (lambda () (interactive) (helm-exit-and-execute-action 'orgnav--new-action)))
    (define-key map (kbd "M-j") 'helm-next-line)
    (define-key map (kbd "M-k") 'helm-previous-line)
    map)
  "Keyboard mapping within helm.")

;; Private state variables
(defvar orgnav--var-buffer nil "Private state.  Which buffer to search.")
(defvar orgnav--var-default-action nil "Private state.  Action to carry out on pressing enter.")
(defvar orgnav--var-depth nil "Private state.  Depth of tree to show.")
(defvar orgnav--var-helm-buffer nil "Private state.  Name of the helm buffer.")
(defvar orgnav--var-point nil "Private state.  Point of tree to start searching.")
(defvar orgnav--var-result nil "Private state.  Variable to store the result of synchronous calls.")
(defvar orgnav--var-last-refile-mark nil "Private state.")


;;; Interactive entry points for searching:
(defun orgnav-search-root (depth default-action)
  "Explore all nodes in the current org document.
Display DEPTH levels.  Run DEFAULT-ACTION on enter."
  (interactive (list 1 'orgnav--goto-action))
  (orgnav-search-subtree nil
                      :depth depth
                      :default-action default-action
                      :helm-buffer-name "*orgnav-search*"))

(defun orgnav-search-subtree (point &rest plist)
  "Explore the org subtree at POINT.  If POINT is nil explore the buffer.
This function returns immediately.
PLIST is a property list with optional properties:
:depth how levels are shown.
:default-action the action run on enter (goto pont by default)
:helm-buffer-name the name of the helm search buffer (of use with `helm-resume')."
  (interactive (list (point)))
  (orgnav--assert-plist plist :depth :default-action :helm-buffer-name :input)
  (let (depth default-action helm-buffer-name input)
    (setq depth (plist-get plist :depth))
    (setq default-action (plist-get plist :default-action))
    (setq helm-buffer-name (plist-get plist :helm-buffer-name))
    (setq input (plist-get plist :input))
    (setq depth (or depth 1))
    (setq default-action (or default-action 'orgnav--goto-action))
    (orgnav--search
     :candidate-func 'orgnav--get-desc-candidates
     :point point
     :depth depth
     :default-action default-action
     :helm-buffer-name helm-buffer-name
     :input input)))

(defun orgnav-search-ancestors (&optional node &rest plist)
  "Search through the ancestors of NODE (by the default the current node).
PLIST is a property list with the following values
:default-action is run on enter (by default jump to node)
:helm-buffer-name is the name of the helm search buffer (useful with ‘helm-resume’)."
  (interactive)
  (orgnav--assert-plist plist :default-action :helm-buffer-name :input)
  (let (default-action helm-buffer-name input)
    (setq default-action (plist-get plist :default-action))
    (setq helm-buffer-name (plist-get plist  :helm-buffer-name))
    (setq input (plist-get plist :input))
    (setq node (or node (save-excursion (org-back-to-heading) (point))))
    (setq default-action (or default-action 'orgnav--goto-action))
    (orgnav--search
     :candidate-func 'orgnav--get-ancestor-candidates
     :point node
     :depth nil
     :default-action default-action
     :helm-buffer-name helm-buffer-name
     :input input)))


;;; Interactive entry points for refiling
(defun orgnav-refile (source-point target-point)
  "Refile the node at SOURCE-POINT to a descendant of the node at TARGET-POINT interactively."
  (interactive (list nil nil))
  (save-excursion
    (if (not (null source-point))
        (goto-char source-point))
    (orgnav-search-subtree target-point
                        :depth orgnav-refile-depth
                        :default-action 'orgnav--refile-to-action
                        :helm-buffer-name "*orgnav refile*")))

(defun orgnav-refile-keep (source-point target-point)
  "Refile the node at SOURCE-POINT to a descendant of the node at TARGET-POINT interactively."
  (interactive (list nil nil))
  (save-excursion
    (if (not (null source-point))
        (goto-char source-point))
    (orgnav-search-subtree target-point
                        :depth orgnav-refile-depth
                        :default-action 'orgnav--refile-keep-to-action
                        :helm-buffer-name "*orgnav refile*")))

(defun orgnav-refile-ancestors (source-point target-point)
  "Refile the node at SOURCE-POINT to an ancestor of the node at TARGET-POINT interactively."
  (interactive (list nil nil))
  (save-excursion
    (if (not (null source-point))
        (goto-char source-point))
    (orgnav-search-ancestors target-point
                          :default-action 'orgnav--refile-to-action
                          :helm-buffer-name "*orgnav refile*")))

(defun orgnav-refile-nearby (&optional levels-up keep)
  "Refile nearby the current point.  Go up LEVELS-UP.  If KEEP keep the original entry."
  (interactive)
  (let* (
         (up-levels (or levels-up 3))
         (refile-function (if keep 'orgnav-refile 'orgnav-refile-keep)))
    (funcall refile-function (point) (save-excursion (org-back-to-heading) (outline-up-heading up-levels t) (point)))))

(defun orgnav-refile-again ()
  "Refile to the location last selected by `orgnav-refile'."
  (interactive)
  (if (null orgnav--var-last-refile-mark)
      (error 'no-last-run))
  (orgnav--refile-to-action (marker-position orgnav--var-last-refile-mark))
  (save-excursion
     (goto-char orgnav--var-last-refile-mark)
     (org-no-properties (org-get-heading))))


;;; Interactive entry points for clocking
(defun orgnav-clock-in (buffer node-point)
  "Clock in to a node in an org buffer BUFFER, starting searching in descendents of NODE-POINT."
  (interactive (list orgnav-clock-buffer nil))
  (save-excursion
    (if (not (null buffer))
        (set-buffer buffer))
    (orgnav-search-subtree node-point
                        :depth orgnav-clock-depth
                        :default-action 'orgnav--clock-action
                        :helm-buffer-name "*orgnav-clock-in*")))

(defun orgnav-search-clocking ()
  "Start a search relative to the currently clocking activity."
  (interactive)
  (save-excursion
    (org-clock-goto)
    (orgnav-search-ancestors)))


;;; Functions that you might want to script
(defun orgnav-jump-interactive (base-filename base-heading)
  "Jump to an ancestor for a heading in BASE-FILENAME called BASE-HEADING."
  (if (not (null base-filename)) (find-file base-filename))
  (orgnav--goto-action
   (orgnav-search-subtree-sync
    (and base-heading (org-find-exact-headline-in-buffer base-heading))
    :depth 2)))

(defun orgnav-search-subtree-sync (point &rest plist)
  "Search the tree at POINT.  Return the `(point)' at the selected node.
PLIST is a property list of settings:
:depth specifies the initial number of levels to show
:helm-buffer-name the name of the helm buffer (useful with ‘helm-resume’)"
  ;; Work around for helm's asychronicity
  (setq orgnav--var-result nil)
  (orgnav--assert-plist plist :depth :helm-buffer-name)
  (apply 'orgnav-search-subtree point :default-action 'orgnav--return-result-action plist)
  ;; RACE CONDITION
  (while (null orgnav--var-result)
    (sit-for 0.05))
  (prog1
      orgnav--var-result
  (setq orgnav--var-result nil)))

(defun orgnav-search-ancestors-sync (point &optional helm-buffer-name)
  "Search the ancestors of the node at POINT.
Return the `(point)' at the selected node.
Start searching in the buffer called HELM-BUFFER-NAME."
  ;; Work around for helm's asychronicity
  (setq orgnav--var-result nil)
  (orgnav-search-ancestors point
                        :default-action 'orgnav--return-result-action
                        :helm-buffer-name helm-buffer-name)
  ;; RACE CONDITION
  (while (null orgnav--var-result)
    (sit-for 0.05))
  (prog1
      orgnav--var-result
  (setq orgnav--var-result nil)))


(defun orgnav-capture-function-global ()
  "A function that can be used with `org-capture-template'.
A *file+function* or *function* capture point to capture to
a location selected using orgnav under the root node.
Here is an example entry:
        `(\"*\" \"Create a new entry\" entry
              (file+function \"test.org\" orgnav-capture-function-global) \"** Title\")'"
  (goto-char (orgnav-search-subtree-sync nil
                                      :depth orgnav-refile-depth
                                      :helm-buffer-name "*orgnav-capture*")))

(defun orgnav-capture-function-relative ()
  "A function that can be used with `org-capture-template'.
A *function* capture point to capture to a location under
the current node selected using orgnav.
Here is an example entry:
        `(\"*\" \"Create a new entry\" entry
               (function orgnav-capture-function-relative) \"** Title\")'"
  (goto-char (orgnav-search-subtree-sync
              (save-excursion
                (outline-back-to-heading 't)
                (point))
              :depth orgnav-refile-depth
              :helm-buffer-name "*orgnav-capture*")))

(defun orgnav-capture-function-ancestors ()
  "A function that can be used with `org-capture-template'.
A *function* capture point'to capture to a ancestor
of the current node.
Here is an example entry:
        (\"*\" \"Create a new entry\" entry (function orgnav-capture-function-ancestor) \"** Title\")"
  (goto-char (orgnav-search-ancestors-sync
              (save-excursion
                (outline-back-to-heading 't)
                (point))
              "*orgnav-capture*")))


;; Private functions
(defun orgnav--search (&rest plist)
  "Generic search function.
PLIST is a property list of *mandatory* values:
`:candidate-func' is a function that returns candidates.
`:point' is where we are searching relative t.
`:depth' is how many levels to display.
`:default-action' is the function to run on carriage return.
`:helm-buffer-name' is name of the helm buffer (relvant for `helm-resume').
`:input' is the initial search term"
  (let (candidate-func point depth default-action helm-buffer-name input)
    (when (not (orgnav--set-eq
              (orgnav--plist-keys plist)
              (list :candidate-func :point :depth :default-action :helm-buffer-name :input)))
      (error "Wrong keys"))
    (setq candidate-func (plist-get plist :candidate-func))
    (setq point (plist-get plist :point))
    (setq depth (plist-get plist :depth))
    (setq input (plist-get plist :input))
    (setq default-action (plist-get plist :default-action))
    (setq helm-buffer-name (plist-get plist :helm-buffer-name))

    ;; Candidate functions appear to
    ;;   not be run in the current buffer, we need to keep track of the buffer
    (setq orgnav--var-buffer (current-buffer))
    (setq orgnav--var-point point)
    (setq orgnav--var-depth depth)
    (setq helm-buffer-name (or helm-buffer-name "*orgnav"))
    (setq orgnav--var-default-action default-action)

    (orgnav--log "orgnav--search candidate-func=%S action=%S header=%S depth=%S input=%S"
              candidate-func
              orgnav--var-default-action
              (orgnav--get-heading orgnav--var-buffer orgnav--var-point)
              orgnav--var-depth
              input)
    (helm
     :sources (list (orgnav--make-source candidate-func default-action))
     :keymap orgnav-mapping
     :input input
     :buffer helm-buffer-name
     :input input)))

(defun orgnav--ancestors ()
  "Find the ancestors of the current org node."
  (save-excursion
    (outline-back-to-heading 't)
    (cons (point) (orgnav--ancestors-rec))))

(defun orgnav--ancestors-rec ()
  "Convenience function used by `orgnav--ancestors'."
  (if
      (condition-case nil
          (progn
            (outline-up-heading 1 't)
            't)
        (error nil))
      (cons (point) (orgnav--ancestors-rec))
    nil))

(defun orgnav--make-source (candidate-func default-action)
  "Make helm source which gets candidates by calling CANDIDATE-FUNC.
by default run DEFAULT-ACTION when return pressed."
  (list
   (cons 'name "HELM at the Emacs")
   (cons 'candidates candidate-func)
   (cons 'action (orgnav--make-actions default-action))))

(defun orgnav--make-actions (default-action)
  "Actions for used by helm.  On return run DEFAULT-ACTION."
  (list
    (cons "Default action" default-action)
    (cons "Decrease depth `M-h`" 'orgnav--decrease-depth-action)
    (cons "Increase depth `M-l`" 'orgnav--increase-depth-action)
    (cons "Explore node `M-.`" 'orgnav--explore-action)
    (cons "Explore parent `M-,`" 'orgnav--explore-parent-action)
    (cons "Create a new node `M-n`" 'orgnav--new-action)
    (cons "Rename node `M-r`" 'orgnav--rename-action)
    (cons "Go to node `M-g`" 'orgnav--goto-action)
    (cons "Clock into the node `M-c`" 'orgnav--clock-action)
    (cons "Explore ancestors of a node `M-a`" 'orgnav-search-ancestors)
    ))

(defun orgnav--make-candidate (point)
  "Construct a helm candidate from a node at POINT."
  (cons
   (orgnav--get-entry-str point)
   point))

(defun orgnav--get-desc-candidates ()
  "Helm candidate function for descendants."
  (with-current-buffer orgnav--var-buffer
    (save-excursion
      (mapcar
       'orgnav--make-candidate
       (let ((current-level
              (if (null orgnav--var-point) 0
                (save-excursion
                  (goto-char orgnav--var-point)
                  (org-outline-level)))))
         (orgnav--filter-by-depth
          (orgnav--get-descendants orgnav--var-point)
          current-level (+ current-level orgnav--var-depth)))))))

(defun orgnav--get-ancestor-candidates ()
  "Find helm candidates for the ancestors of the location set by a search function."
  (with-current-buffer orgnav--var-buffer
    (save-excursion
      (if orgnav--var-point
          (goto-char orgnav--var-point))
      (mapcar 'orgnav--make-candidate
              (orgnav--ancestors)))))

(defun orgnav--get-entry-str (point)
  "How orgnav should represent a the node at POINT."
  (save-excursion
    (goto-char point)
    (concat (s-repeat (org-outline-level) "*") " " (org-get-heading))))

(defun orgnav--filter-by-depth (headings min-level max-level)
  "Filter the nodes at points in HEADINGS.
Only returning those between with a level better MIN-LEVEL and MAX-LEVEL."
  (-filter (lambda (x)
             (save-excursion
               (goto-char x)
               (and
                (or (null min-level)
                    (>= (org-outline-level) min-level))
                (or (null max-level)
                    (<= (org-outline-level) max-level)))))
           headings))


;;; Actions
(defun orgnav--goto-action (helm-entry)
  "Go to the node represented by HELM-ENTRY."
  (interactive)
  (orgnav--log "Action: go to %S" helm-entry)
  (goto-char helm-entry)
  (org-reveal))

(defun orgnav--explore-action (helm-entry)
  "Start search again from HELM-ENTRY."
  (orgnav--log "Action: explore %S" helm-entry)
  (orgnav-search-subtree helm-entry
                      :depth 1
                      :default-action orgnav--var-default-action
                      :helm-buffer-name orgnav--var-helm-buffer))

(defun orgnav--explore-ancestors-action (helm-entry)
  "Start search again looking ancestors of HELM-ENTRY."
  (orgnav--log "Action: explore ancestors of %S" helm-entry)
  (orgnav-search-ancestors
   helm-entry
   :depth orgnav--var-default-action
   :helm-buffer-name orgnav--var-helm-buffer))

(defun orgnav--explore-parent-action (ignored)
  "Start search again from one level higher.  Ignore IGNORED."
  (orgnav--log "Action: explore parent of search at %S"
            orgnav--var-point)
  (orgnav-search-subtree (orgnav--get-parent orgnav--var-point)
                      :depth 1
                      :default-action orgnav--var-default-action
                      :helm-buffer-name orgnav--var-helm-buffer))

(defun orgnav--increase-depth-action (ignored)
  "Search again showing nodes at a greater depth.  IGNORED is ignored."
  (orgnav--log "Action: Increasing depth of search")
  (orgnav-search-subtree orgnav--var-point
                      :depth (+ orgnav--var-depth 1)
                      :default-action orgnav--var-default-action
                      :helm-buffer-name orgnav--var-helm-buffer
                      :input (orgnav--get-input)))

(defun orgnav--decrease-depth-action (ignored)
  "Search again hiding more descendents.  IGNORED is ignored."
  (orgnav--log "Action: decrease depth of search")
  (orgnav-search-subtree orgnav--var-point
                      :depth (max (- orgnav--var-depth 1) 1)
                      :default-action orgnav--var-default-action
                      :helm-buffer-name orgnav--var-helm-buffer
                      :input (orgnav--get-input)))

(defun orgnav--new-action (helm-entry)
  "Create child under the select HELM-ENTRY.  IGNORED is ignored."
  (orgnav--log "Action: Creating a new node under %S" helm-entry)
  (let* (
         (point-function (lambda ()  (set-buffer orgnav--var-buffer) (goto-char helm-entry)))
         (org-capture-templates (list (list "." "Default action" 'entry (list 'function point-function) "* %(read-string \"Name\")"))))
    (org-capture nil ".")))

(defun orgnav--return-result-action (helm-entry)
  "A convenience action for synchronouse functions.
Store the location of HELM-ENTRY so that the synchronous functions can return them."
  (orgnav--log "Action: Saving %S to return" helm-entry)
  (setq orgnav--var-result helm-entry))

(defun orgnav--rename-action (helm-entry)
  "Action to rename HELM-ENTRY."
  (orgnav--log "Action: renaming %S" helm-entry)
  (let (heading)
    (setq heading
          (read-string "New name" (save-excursion
                              (goto-char helm-entry)
                              (org-get-heading))))
    (orgnav--rename helm-entry heading)
    (orgnav-search-subtree orgnav--var-point
                        :depth orgnav--var-depth
                        :default-action orgnav--var-default-action
                        :helm-buffer-name orgnav--var-helm-buffer
                        :input (orgnav--get-input))))

(defun orgnav--clock-action (helm-entry)
  "Clock into the selected HELM-ENTRY."
  (orgnav--log "Action: Clocking into %S" helm-entry)
  (save-excursion
    (goto-char helm-entry)
    (org-clock-in)))

(defun orgnav--refile-to-action (helm-entry)
  "Action used by `orgnav-refile` to refile to the selected entry HELM-ENTRY."
  (orgnav--log "Action: refiling %S to %S" (point) helm-entry)
  (setq orgnav--var-last-refile-mark (make-marker))
  (set-marker orgnav--var-last-refile-mark helm-entry)
  (org-refile nil nil (list nil buffer-file-name nil helm-entry)))

(defun orgnav--refile-keep-to-action (helm-entry)
  "Action used by `orgnav-refile-keep` to refile to a selected HELM-ENTRY.
The original entry is kept unlike `orgnav--refile-to-action'."
  (orgnav--log "Action: refiling %S to %S" (point) helm-entry)
  (setq orgnav--var-last-refile-mark (make-marker))
  (set-marker orgnav--var-last-refile-mark helm-entry)
  (org-refile 3 nil (list nil buffer-file-name nil helm-entry)))

;;; Utility functions
(defun orgnav--get-parent (point)
  "Get the parent of the node at POINT."
  (save-excursion
    (goto-char point)
    (condition-case nil
        (progn
          (outline-up-heading 1 t)
          (point))
      (error nil))))

(defun orgnav--get-heading (buffer point)
  "Get the heading of an org element in BUFFER at POINT."
  (with-current-buffer buffer
    (save-excursion
      (or (point)
          (progn
            (goto-char point)
            (substring-no-properties (org-get-heading)))))))

(defun orgnav--get-descendants (tree)
  "Get the positions of all the headings under the tree at TREE."
  (interactive)
  (let ((result))
    (save-excursion
      (if (not (null tree)) (goto-char tree))
      (if
          (null tree)
          (org-map-region (lambda () (add-to-list 'result (point) 't)) (point-min) (point-max))
        (org-map-tree (lambda () (add-to-list 'result (point) 't)))))
    result))

(defun orgnav--rename (point name)
  "Rename the node at POINT to NAME."
  (let (new-heading)
    (save-excursion
      (goto-char point)
      (setq new-heading
            (concat (s-repeat (org-outline-level) "*") " " name))

      (beginning-of-line)
      (kill-line)
      (insert new-heading))))

(defun orgnav--log (format-string &rest args)
  "Print logging depending of ORGNAV-LOG variable.  FORMAT-STRING  and ARGS have the same meanings as message."
  (when orgnav-log
    (message (apply 'format format-string args))))

(defun orgnav--assert-plist (plist &rest members)
  "Ensure that the property list PLIST has only keys in MEMBERS."
  (when (not  (cl-subsetp (orgnav--plist-keys plist) members))
      (error (format "%S plist contains keys not in %S" plist members))))

(defun orgnav--plist-keys (plist)
  "Return a list of the keys in PLIST."
  (if (null plist)
      nil
    (cons (car plist) (orgnav--plist-keys (cddr plist)))))

(defun orgnav--set-eq (set1 set2)
  "Test if lists SET1 and SET2 have the same members."
  (and
   (cl-subsetp set1 set2)
   (cl-subsetp set2 set1)))

(defun orgnav--get-input ()
  "Get the current input of the helm search."
  helm-input)

(provide 'orgnav)
;;; orgnav.el ends here
