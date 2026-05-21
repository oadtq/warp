-- Solo-style project-grouped tabs: persist the project a tab belongs to and
-- whether it was launched as a CLI agent vs. a plain terminal so the
-- vertical-tabs sidebar can restore the same Terminals / Agents grouping
-- across restarts. NULL on either column → the tab restores into the
-- "Ungrouped" bucket (graceful fallback for older rows / non-project tabs).
ALTER TABLE tabs ADD project_path TEXT;
ALTER TABLE tabs ADD tab_kind TEXT;
