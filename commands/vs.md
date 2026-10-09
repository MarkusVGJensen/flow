---
description: "Optional, for Visual Studio users: open a file at a line, from the current worktree"
argument-hint: "<file>[:line]"
allowed-tools: ["Bash", "Glob"]
---

# Open in Visual Studio

Open `$ARGUMENTS` in the running Visual Studio instance, or a new one. An optional convenience for
Visual Studio users on Windows; nothing else in flow depends on it.

Resolve the path against the current worktree; if the argument is a bare filename, Glob for it and ask
only when there is genuine ambiguity.

```
devenv /edit "<absolute path>"                       # file
devenv /edit "<absolute path>" /command "Edit.GoTo <line>"   # file at a line
```

`/edit` reuses an open instance instead of starting a second one. If `devenv` is not on PATH, say so
and print the absolute path so the user can open it themselves — do not go hunting the install.
