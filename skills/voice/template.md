# Voice template

Copy this file, fill it in, and list it under `voice:` in `$XDG_CONFIG_HOME/voice/config.md`, or `~/.config/voice/config.md` when that variable is unset.
Or point the voice skill at a folder of things you wrote, or let it interview you, and it fills this in for you.
Either way, keep the raw writing it was built from listed under `samples:` in the same config, so the skill can go back to it when the voice drifts.

Delete every line of guidance (the lines in *italics*) once you have replaced it.
Keep the section headers; the skill reads the file top to bottom and the headers tell it what each part is.

Frequency labels, used on every rule below:

- **hard**: never violated. Reserve for things you would be embarrassed to have posted.
- **strong**: true about 3 times in 4. The skill follows it unless the content pushes back.
- **light**: a preference. The skill uses judgment. Unlabelled rules are light.

Lean towards light.
A file of hard rules produces a caricature.

---

# Voice: <your name>

## Who is writing

*One paragraph. Your role, the kinds of things you post, who reads them. "Staff engineer, mostly PR reviews and Slack to a team of 8, occasional blog post."*

## Samples

*3 to 6 pieces you actually wrote and would post again. Verbatim, unedited. Different channels are better than one. This is the highest-signal section in the file; the skill matches rhythm and register against these before it reads any rule. When an excerpt came from a file in your samples folder, name the file above it and say whether you typed it or rewrote an agent draft, so recalibration can find the rest and tell your writing from drafts you only approved.*

### Slack

<!-- from: ~/writing/samples/slack-2026-03.txt, typed by me -->
```text
<paste>
```

### PR comment

```text
<paste>
```

### Email

```text
<paste>
```

## Rhythm

*How long your sentences and paragraphs run, and how much you vary them. Whether you use fragments. Whether you open a paragraph with "But" or "So".*

- strong: ...
- light: ...

## Tone

*How direct you are. Whether you hedge and how ("I think", "probably"). Whether you use humour and what kind. First person, second person. How you sound when you are certain and when you are not.*

- strong: ...
- light: ...

## Formatting

*Contractions. Emoji. Exclamation marks. Bold. Headers. Bullets. Code blocks. Numbers as digits or words. Sentence case or title case in headers.*

- hard: ...
- strong: ...

## Per channel

*Where your voice shifts. Most people are looser on Slack than on email and looser on email than in public. Say how. A line per channel is enough.*

- Slack / Discord: ...
- PR review comments: ...
- Issues: ...
- Email: ...
- Public (blog, LinkedIn, release notes): ...

## Situations

*How you handle the moments that are easy to get wrong in someone else's voice.*

- Telling someone their work has a problem: ...
- Disagreeing with a decision: ...
- Saying no: ...
- Announcing something you built: ...
- Asking for help: ...
- Opening a message: ...
- Closing a message: ...

## Never

*Words and phrases you do not use. Also anything from the skill's built-in floor you want to make stricter. One per line.*

- hard: ...

## Always fine

*Anything the skill's built-in floor bans that you use on purpose and want back. Em dashes, a rule of three, a word from the dead-vocabulary list that is plainly right in your field. One per line, with the reason if there is one.*

- ...

## Overused

*Words and tics you catch yourself repeating. The skill will ration them.*

- ...
