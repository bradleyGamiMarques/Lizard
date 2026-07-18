/**
 * Commitlint configuration.
 *
 * Enforces Conventional Commits:
 *   <type>[optional scope]: <description>
 *
 * Examples:
 *   feat(infra): add CloudFormation IaC
 *   fix(alarm): handle missing billing threshold
 *   chore(ci): add lefthook hooks
 */
export default {
  extends: ['@commitlint/config-conventional'],

  rules: {
    /**
     * Keep the subject readable in terminals, GitHub UI, and changelogs.
     */
    'header-max-length': [2, 'always', 70],

    /**
     * Require lower-case commit types like:
     *   feat, fix, chore
     */
    'type-case': [2, 'always', 'lower-case'],

    /**
     * Require the type to be one of the conventional project-approved types.
     */
    'type-enum': [
      2,
      'always',
      [
        'build',
        'chore',
        'ci',
        'docs',
        'feat',
        'fix',
        'perf',
        'refactor',
        'revert',
        'style',
        'test',
      ],
    ],

    /**
     * Keep scopes consistent when used.
     *
     * Valid:
     *   feat(infra): add billing alarm
     *
     * Also valid:
     *   feat: add billing alarm
     */
    'scope-case': [2, 'always', 'lower-case'],

    /**
     * Conventional Commit subjects should not end with punctuation.
     */
    'subject-full-stop': [2, 'never', ['.', '!', '?']],

    /**
     * Prefer imperative mood:
     *   fix(alarm): handle timeout
     * instead of:
     *   fix(alarm): handled timeout
     */
    'subject-case': [
      2,
      'never',
      ['sentence-case', 'start-case', 'pascal-case', 'upper-case'],
    ],

    /**
     * Require a blank line between the subject and the body. Pairs
     * with footer-leading-blank: without this rule, a mashed-together
     * commit (no blank lines anywhere) slips through because git's
     * trailer parser fails to detect the Co-Authored-By line as a
     * trailer, so footer-leading-blank never fires. Together the two
     * rules enforce the canonical Conventional Commits shape end-to-end.
     */
    'body-leading-blank': [2, 'always'],

    /**
     * Require a blank line between the body and any footer (e.g. the
     * Co-Authored-By trailer). Best-effort — the conventional-commits
     * parser only recognizes a footer when there's already a blank
     * line above it, so a trailer glued directly to the body absorbs
     * into the body and this rule does not fire. body-leading-blank
     * above is the real defense against the common mashed-together
     * mistake; this rule fails the rarer cases where the parser does
     * recognize a trailer (typically multi-paragraph commits) so they
     * fail outright instead of warning silently.
     */
    'footer-leading-blank': [2, 'always'],
  },
};
