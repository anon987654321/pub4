# Prompts

Do all the below silently (in **quiet mode**) without summarizing or explaining. When iterating, show only the final iteration.
Proceed automatically to the next file/task without requiring my permission.

1. **ANALYZE**

   1.1. Start with `README.md` if available.
   1.2. Review every line of every file (exclude temporary and dot files).

2. **IMPROVE**

   2.1. Don't delete important functions (unless marked redundant). Don't truncate, omit, or simplify anything. And lastly, don't add new features without asking for permission.
   2.2. Flesh out, embellish, refine, and streamline iteratively until production-ready. Identify and fix bugs, syntax errors, and logical inconsistencies along the way. Continuously compare the new code with the original to ensure nothing is lost.
   2.3. Avoid hardcoding as opposed to more dynamic solutions.
2.4. Consolidate all changes into a one-time Zsh installer-type script with the necessary shell commands and Ruby code grouped by feature and chronology, each separated with `# -- <GIT COMMIT MESSAGE IN UPPERCASE> --\n\n`.

3. **STYLE GUIDE**

Strictly enforce the following guidelines. This is not up for discussion; under no circumstance must you deviate or skip them:

   3.1. Use double quotes, two-space indents, and wrap code blocks in four backticks.
   3.2. Use brief, clear ELI5-style English for non-programmers, adhering to Strunk & White's guidelines.

   3.3. **HTML/CSS**
      3.3.1. Write clean, semantic HTML5 and SCSS; avoid unnecessary containers. Use mobile-first design; place desktop-specific rules at the bottom.
      3.3.2. Sort SCSS rules by feature and properties alphabetically.
      3.3.3. Target elements directly; avoid unnecessary class names.
      3.3.4. Use underscores, not dashes in CSS class names.
      3.3.5. Prefer modern CSS methods (flexbox, grid layouts, etc.) over outdated techniques (floats, clears, positioning, etc.).

   3.4. **RUBY ON RAILS**
      3.4.1. Use Rails tag helpers instead of standard HTML tags, ie. `<%= tag.p t("hello_world") %>`.
      3.4.2. Break views into partials where feasible.
      3.4.3. Ensure the app uses the latest features, such as Turbo, Stimulus.js, StimulusReflex, and stimulus-components.com for improved UI/UX.
      3.4.4. Create or update I18n YAML files for English and Norwegian.

--

- Gather the latest research from [arXiv](https://arxiv.org/) for improvements.

