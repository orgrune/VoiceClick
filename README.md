# VoiceClick

A small macOS app that shows a web page (defaults to your Quantic lesson), listens to
your voice, and clicks the button whose text matches what you say.

## Build and run

```bash
./build.sh && open build/VoiceClick.app
```

Needs Xcode (or the command line tools) for `swiftc`. The first time you press
**Start listening**, macOS asks for Microphone and Speech Recognition permission.

## Using it

1. Log in to Quantic inside the app (email + password is the most reliable; the
   session is remembered between launches).
2. Press **Start listening** (or ⌘L).
3. Say what you see on a button: “Get Started”, “Continue”, “Submit”, or the text
   of an answer option.

Other things you can say:

- “option B”, “B”, “second one”, “number 3” — pick an answer by letter or position
- “next”, “go on”, “start”, “done” — aliases for Continue / Get Started / Submit
- “scroll down”, “scroll up”, “go back”, “reload”
- “stop listening”

The **You can say** panel lists every clickable label currently on the page
(answer-style options are marked with ◦). The text field under *Last command*
lets you type a command to test the matching without speaking.
