# API Key Setup Instructions

## For Development

1. Copy the example configuration file:
   ```bash
   cp VoiceControl/Config/Secrets.xcconfig.example VoiceControl/Config/Secrets.xcconfig
   ```

2. Edit `VoiceControl/Config/Secrets.xcconfig` and replace `YOUR_API_KEY_HERE` with your actual OpenAI API key:
   ```
   OPENAI_API_KEY = sk-proj-YOUR_ACTUAL_API_KEY_HERE
   ```

3. In Xcode, you need to configure the project to use the xcconfig file:
   - Select your project in the navigator
   - Select the VoiceControl target
   - Go to the Info tab
   - Under Configurations, set both Debug and Release to use "Base" configuration file
   - You may need to manually browse and select `VoiceControl/Config/Base.xcconfig`

4. Clean and rebuild the project (⌘⇧K then ⌘B)

## For Production/Distribution

The API key will be embedded in the app bundle through the build process. The key is read from:
1. Environment variable `OPENAI_API_KEY` (for development)
2. Info.plist value `OpenAIAPIKey` (for production, set via xcconfig)
3. User config file at `~/Library/Application Support/VoiceControl/config.json` (optional fallback)

## Security Notes

- **NEVER** commit `Secrets.xcconfig` to version control
- The exposed API key in the git history should be rotated immediately
- Consider implementing additional obfuscation for production releases
- The `.gitignore` file is configured to exclude sensitive files

## Alternative: User-Provided API Keys

If you want users to provide their own API keys, they can create:
```bash
mkdir -p ~/Library/Application\ Support/VoiceControl
echo '{"openai_api_key": "their-api-key-here"}' > ~/Library/Application\ Support/VoiceControl/config.json
```