# Podfile for VoiceControl

platform :osx, '13.0'
use_frameworks!

target 'VoiceControl' do
  # VAD Library
  pod 'RealTimeCutVADLibrary', :git => 'https://github.com/helloooideeeeea/RealTimeCutVADLibrary.git'
end

post_install do |installer|
  # Fix xcconfig to include our base configuration
  installer.aggregate_targets.each do |target|
    if target.name == 'Pods-VoiceControl'
      ['debug', 'release'].each do |config_name|
        xcconfig_path = "#{installer.sandbox.root}/Target Support Files/#{target.name}/#{target.name}.#{config_name}.xcconfig"
        if File.exist?(xcconfig_path)
          xcconfig_content = File.read(xcconfig_path)
          base_include = "#include \"../../../VoiceControl/Config/Base.xcconfig\"\n\n"
          unless xcconfig_content.include?("Base.xcconfig")
            File.open(xcconfig_path, 'w') do |file|
              file.write(base_include + xcconfig_content)
            end
          end
        end
      end
    end
  end
  
  # Original post_install content
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Disable code signing for pods
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
      config.build_settings['CODE_SIGN_IDENTITY'] = ''
      
      # Ensure frameworks are built for the right platform
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
      
      # Disable hardened runtime for pods
      config.build_settings['ENABLE_HARDENED_RUNTIME'] = 'NO'
      
      # Fix sandbox issues
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      config.build_settings['ENABLE_APP_SANDBOX'] = 'NO'
    end
  end
  
  # Fix the main project settings too
  installer.aggregate_targets.each do |target|
    target.xcconfigs.each do |config_name, config_file|
      config_file.attributes['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      xcconfig_path = target.xcconfig_path(config_name)
      config_file.save_as(xcconfig_path)
    end
  end
end