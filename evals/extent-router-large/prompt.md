---
description: Work that spans many packages and long parallel strands stops and asks before spending.
tags: [router]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 8
---
Use flow's extent router to size this task: migrate the persistence layer of a large monorepo from
one ORM to another. About 300 files across 9 packages change, each package has its own test suite
and owner, and the packages depend on each other's schema decisions as the migration goes.
