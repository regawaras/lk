//! Built-in tag aliases shipped with LogKlerk.
//!
//! Each entry maps a command alias to a taxonomy prefix, e.g. `todo` logs as
//! `[[TODO]] >> <text>`. Users can add their own with `lkset`, `lkfiles` and
//! `lknote`; user definitions override these defaults.

/// (alias, prefix)
pub const BUILTIN_TAGS: &[(&str, &str)] = &[
    ("todo", "[[TODO]] >>"),
    ("ideas", "[[IDEAS]] >>"),
    ("problems", "[[Problems/Troubleshooting]] >>"),
    ("solved", "[[Problems Solved]] >>"),
    ("bugs", "[[Bugs]] >>"),
    ("questions", "[[Questions]] >>"),
    ("note", "[[Note]] >>"),
    ("info", "[[Information]] >>"),
    ("ref", "[[Reference]] >>"),
    ("lesson", "[[Lesson]] >>"),
    ("reflection", "[[Reflections]] >>"),
    ("experiment", "[[Experimenting]] >>"),
    ("hypothesis", "[[Hypothesis]] >>"),
    ("failed", "[[Failed]] >>"),
    ("events", "[[Events]] >>"),
    ("activity", "[[Activity]] >>"),
    ("reminder", "[[Reminder]] >>"),
    ("wishlist", "[[Wishlist]] >>"),
    ("quotes", "[[Quotes]] >>"),
    ("com", "[[Commentary]] >>"),
    ("discussion", "[[Discussion]] >>"),
    ("productivity", "[[Productivity]] >>"),
    ("health", "[[Health]] >>"),
    ("github", "[[GitHub]] >>"),
    ("testing", "[[Testing]] >>"),
    ("tomorrow", "[[Plan for Tomorrow]] >>"),
    ("plan", "![PLAN]! >>"),
];

/// (alias, folder, prefix): entries written to a standalone folder instead of
/// the daily vault file.
pub const BUILTIN_EXCLUSIVE: &[(&str, &str, &str)] = &[("private", "Private", "[[Private]] >>")];
