# SathiAi

**Sathi** is a Generative AI client plugin designed particularly for **Dank Material Shell**. It enables you to interact with Large Language Models (LLMs) directly from your desktop shell making it easy to ask questions, find commands without needing to switch apps or open a browser.

https://github.com/user-attachments/assets/0e90c1ff-e7d1-4b15-98a0-434727c99665

## Features

- 💬 **Desktop Chat Interface**: Talk to AI without opening a browser.
- ⚡ **Multi-Provider Support**: Supports **Google Gemini**, **OpenAI**, **Anthropic**, **Ollama**, **LMStudio** models.
- 🎨 **Markdown Support**: Chat bubbles support markdown formatting, clickable links and copying to clipboard.
- 🎭 **Context Control**: Allows **you** to set and specify context details for how you want the AI to behave.
- 🛠️ **Configurable**: Set your API keys and endpoints directly in settings.
- 📌 **Pin to Top**: Keep the chat visible while you work. You can still use other apps underneath it.
- 🚀 **Instant-_ish_ Open**: Speedy window access to make it faster to access your conversations.

## Limitations

- Limited context to the last _x,y_ messages that can be set. (Running a dameon or service or even a process could work around this but complicates install and use.)
- When listing models right now we get all available models offered by a service - many of which may not be useful. Users will need some idea of the model they want to use.
- Sessions are cleared when logging out and not saved.

## Installation

### Prerequisites

- Dank Material Shell
- A supported AI Provider ([Ollama](https://ollama.com), [Gemini](https://aistudio.google.com/), [OpenAI](https://platform.openai.com), [Anthropic](https://platform.claude.com), [LMStudio](https://lmstudio.ai/))

### 1. Install Plugin Dependencies

- Install the plugin to your plugins directory (`~/.config/DankMaterialShell/plugins`) by default.
- Enable the plugin in the plugins screen.
- Add the widget to your widgets tab.
- (Optional) - add a shortcut key to open the plugin ie in niri/config.kdl you can add something like: `Mod+Shift+Space { spawn-sh "dms ipc call widget toggle sathiAi"; }`

### 2. Configuration

1. Enable the plugin in Dank Settings.
2. Open the **Sathi** settings page.
3. Configure your AI providers:
   - **Google Gemini**: Enter your API Key from [Google AI Studio](https://aistudio.google.com/).
   - **OpenAI**: Enter your API Key from [OpenAI Platform](https://platform.openai.com/api-keys).
   - **Anthropic**: Enter your API Key from [Claude Platform](https://platform.claude.com/settings/keys).
   - **Ollama**: Enter your local server URL (default: `http://localhost:11434`).
   - **LMStudio**: Enter your local LMStudio server URL (default: `http://localhost:1234`). Uses the OpenAI API format.
4. (Optional) Set a custom **System Prompt** to define the AI's persona.

## 3. Usage

1. Click the **Sathi** widget in your shelf/panel.
2. Select your preferred model from the dropdown (Gemini models and local Ollama models will appear mixed).
3. Type your message and press Enter!

## Troubleshooting

- **"Script failed"** or **missing responses**:
  - Ensure your API Key is correct.
  - Check the `dms` logs (`DMS_LOG_LEVEL=debug dms run`) for more details.

## Motivation

- Dank Matter Shell is dope as hell. Actually made me like my desktop.
- Niri is amazing it made me want to use my laptop.
- I find Ai convenient but all the ai clients i tried just didn't fit with my new found niri flow.
- DMS plugin system was easy to work with and i wanted to learn and try something.

## Ai Disclosure

- While I take pride in writing a chunk of the code by hand and resolving logic that the AI just couldn't get right, I also used AI to do a bunch of tedious, monotonous tasks, which in my opinion is the perfect use of it.

## Sceenshots

- <img width="1386" height="938" alt="sathi-ai" src="https://github.com/user-attachments/assets/9721effc-c5e0-4269-8170-a4e0b8a95d02" />

## Attributions

<a href="https://www.flaticon.com/free-icons/sparkle" title="sparkle icons">Sparkle icons created by Muhammad_Usman - Flaticon</a>

## License

[MIT](LICENSE)
