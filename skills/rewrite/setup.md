# Voice setup and recalibration

`SKILL.md` in this directory defines the config lookup and the config directory.
A path the user gives has a leading `~` expanded to `$HOME` before any check.

## The config

`config.md` in the config directory holds two lists:

```markdown
# voice config
voice:
- ~/.config/voice/voice.md        # rules plus excerpted samples, read before drafting
samples:
- ~/writing/samples/              # the user's own writing, kept for recalibration
- ~/writing/emails-i-liked.md
```

Own writing means typed by the user, or an agent draft the user rewrote in their own words.
A draft the user only approved or lightly edited never goes into `samples`.

## Where this skill writes

The config directory is the one place this skill writes on its own, and new files go there.
Create the config directory when it is missing.
Before writing, resolve the config directory to its real path, and the target to its real path, or its nearest existing directory when the target does not exist yet, and refuse when the target's is outside the config directory's, unless it is the one path the user approved as below.
Two other writes are allowed, each only after the user approves that specific change: adding a file to a listed samples folder, and editing a voice file listed under `voice` that sits outside the config directory.
Approval means the user saw the exact change and said yes.
A request such as "loosen that rule" asks for a proposal, and the file stays untouched until the user approves the diff.
Change only what the user named, and ask when you cannot tell which lines they mean.
Nothing else on the machine is written.
Show the config and the voice file to the user before saving either.

## First run

Stop before drafting.
Ask once, in a single question, which of the three paths below fits, and say the answer will be saved to the config path.
Reusing an existing voice file is path A, which only the user chooses, by naming the file, so never suggest a location for one.

**Path A: the user has a voice file.**
Ask for the path or paths, confirm each exists, list it under `voice`, and read it.
Ask whether they also have a folder of their own writing, and when they do, ask for its path, confirm it exists, and list it under `samples`.
Then continue with what the user asked for.

**Path B: the user has a folder of their writing.**
Ask for the path, and confirm it is a directory with a file tool, such as listing its `.md` and `.txt` files, so the path never becomes shell source.
After one more invalid path, offer Path C.
Read it as `SKILL.md` reads a directory in a list.
Skip a file that says it was an agent draft the user only approved, as Building the file does.
Build a new voice file as "Building the file" says, with 3 to 6 excerpts that differ in channel and length, each a paragraph or two.
When the folder yields fewer than 3 usable excerpts, say so and ask for more writing, or build from the ones there are without repeating or inventing any.
Derive the rules from the whole folder, and offer the round-two questions as optional.
List the folder under `samples` and the new file under `voice`.
Ask whether they keep rules about their writing in a file of their own.
When they do, list it under `voice` ahead of the built file, and keep the built file to samples and what they show about register.

**Path C: the user has nothing yet.**
Run the interview, build the voice file from `template.md` in this directory, save it as `voice.md` in the config directory, and list it under `voice`.
Save the pasted samples to `samples.md` in the config directory and list that file under `samples`.

The user can rerun setup at any time, and an existing config is edited in place.

## The interview

Collect answers as free text.
Round one cannot be skipped:

> Paste 3 to 5 things you actually wrote and are happy with.
> A Slack message, a PR comment, an email, a paragraph from a post.
> Different channels are better than one.
> Unedited is better than polished.

Round two is one message with these questions, and the user answers whichever they like:

1. How do you open a message to a teammate, and how do you close one?
2. How do you tell someone their work has a problem?
3. Words or phrases you never use, and words you catch yourself overusing.
4. Contractions, emoji, exclamation marks, swearing: which ones, where?
5. How does your Slack differ from your email and your public writing?
6. How long is too long, and what makes you stop reading someone else's message?
7. Anything you do on purpose that most people around you don't?

## Building the file

Copy the samples verbatim under the samples section.
Above each excerpt, record its source file and whether the user typed it or rewrote an agent draft.
Leave out a source file that says it was an agent draft the user only approved.
Quote the user's answers where they are already a rule ("I never say 'circle back'" goes in as written).
Derive the rest from the samples: sentence and paragraph length, openings, disagreement, and formality per channel.
Label every derived rule hard, strong, or light as the template defines them, and lean towards light, since a file of hard rules produces a caricature.
Show the whole file and ask what is wrong with it before saving.

## Recalibrating

Read the `samples` list in full as `SKILL.md` reads a list, including anything added since the voice file was built, and skip a file that says it was an agent draft the user only approved.
Swap excerpts that no longer represent the samples for ones that do, and loosen or remove rules the samples contradict.
A rule is contradicted only when a sample does the opposite, and a rule no sample exercises stays as it is.
For a rule the user typed by hand, say that the samples disagree with it and let the user decide.
Show the changes before saving, and keep the `samples` list as it was unless the user adds to it.

A config with no `samples` entry cannot recalibrate.
Say so, and offer to collect some: a folder the user points at, or pasted pieces appended to `samples.md` in the config directory, created when missing.
Add the chosen path to the config's `samples` list in the same edit.
