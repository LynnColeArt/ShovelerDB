# AGENTS.md

## Engineering Philosophy

This project values small, direct, understandable code.

Prefer the simplest implementation that solves the problem without creating downstream complexity. Simple does not mean simplistic. It means the shortest clear path from point A to point B, with the fewest moving parts required to keep the system correct, maintainable, and easy to reason about.

Avoid enterprise-style ceremony unless it is clearly justified by the problem.

## Core Principles

### Code Minimalism

Write less code when less code is enough.

Every abstraction, dependency, layer, helper, interface, or framework must earn its place. If the code is easier to understand without it, remove it.

Do not build speculative flexibility. Do not add architecture for imagined future requirements. Solve the current problem cleanly, leaving the code easy to change later.

### DRY, Correctly Applied

Avoid needless repetition, but do not create premature abstractions just to remove duplicated lines.

Duplication is sometimes cheaper than indirection. Abstract only when the shared shape is real, stable, and improves clarity.

Work from first principles whenever possible.

### Test-Driven Development

Use TDD as a design discipline.

Remember the three rules of TDD:

1. Do not write production code unless it is needed to make a failing test pass.
2. Do not write more of a test than is sufficient to fail.
3. Do not write more production code than is sufficient to pass the failing test.

Tests should drive the shape of the code, not merely decorate it after the fact.

### Separation of Concerns

Keep concerns compartmentalized and easy to reason about.

Each module should have a clear responsibility. Avoid mixing unrelated policy, IO, business logic, parsing, formatting, state management, and orchestration unless the problem is genuinely too small to benefit from separation.

### Fits-in-Head Rule

A module should fit in a developer's head.

When reading a module, it should be possible to understand what it does, why it exists, and how it interacts with the rest of the system without spelunking through a maze of hidden dependencies.

If a module becomes difficult to hold mentally, split it by responsibility.

## Zig Mindset

Approach this project with a pure Zig mindset:

* Be explicit.
* Prefer simple control flow.
* Prefer clear ownership.
* Prefer concrete code over clever abstraction.
* Treat allocation, failure, and state as things that must be visible and intentional.
* Avoid magic.
* Avoid hidden behavior.
* Make the cost of code obvious.

The goal is not to imitate Zig syntax everywhere. The goal is to carry Zig's discipline into the whole project.

## Comments

Comments are a time machine for the team.

Use comments to explain why something exists, not what the code mechanically does.

Good comments clarify intent, constraints, tradeoffs, surprising decisions, or historical context. Bad comments narrate obvious code.

Use comments sparingly. Add them when the code diverges from an expected outcome or pattern, or when future readers will need context they cannot infer from the implementation alone.

## Review Standard

Assume this code will be reviewed by a QA agent with standards higher than your own.

Before presenting work as complete, check for:

* Unnecessary abstractions
* Unjustified dependencies
* Overly clever control flow
* Hidden state
* Poor separation of concerns
* Missing tests
* Weak error handling
* Comments that explain what instead of why
* Code that solves a larger problem than the one actually requested

If the solution feels impressive but not obvious, simplify it.

## Antipatterns

Avoid:

* Enterprise ceremonial dogma
* Abstractions that cannot be justified
* Dependencies that cannot be justified
* Cleverness
* Speculative architecture
* Configuration sprawl
* Hidden global state
* Framework-first thinking
* Overbroad modules
* Tests that only verify mocks
* Comments that restate the code
* Indirection that exists only to look professional

Prefer code that is boring, sharp, and correct.

