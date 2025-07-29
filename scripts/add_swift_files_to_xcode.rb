#!/usr/bin/env ruby

# This script adds Swift files to an Xcode project
# It requires sudo gem install xcodeproj

require 'pathname'

# Try to load xcodeproj, install if not available
begin
  require 'xcodeproj'
rescue LoadError
  puts "Installing xcodeproj gem..."
  system("sudo gem install xcodeproj")
  require 'xcodeproj'
end

# Configuration
PROJECT_PATH = 'VoiceControl.xcodeproj'
TARGET_NAME = 'VoiceControl'

# Files to add with their group paths
FILES_TO_ADD = [
  { path: 'VoiceControl/Core/OpenAIService.swift', group_path: ['VoiceControl', 'Core'] },
  { path: 'VoiceControl/Core/GPTService.swift', group_path: ['VoiceControl', 'Core'] },
  { path: 'VoiceControl/Features/EditMode/EditManager.swift', group_path: ['VoiceControl', 'Features', 'EditMode'] },
  { path: 'VoiceControl/Features/EditMode/EditModeHUD.swift', group_path: ['VoiceControl', 'Features', 'EditMode'] }
]

# Open the project
project = Xcodeproj::Project.open(PROJECT_PATH)

# Find the target
target = project.targets.find { |t| t.name == TARGET_NAME }
unless target
  puts "Error: Target '#{TARGET_NAME}' not found"
  exit 1
end

# Helper method to find or create a group
def find_or_create_group(parent, name)
  group = parent.children.find { |child| child.is_a?(Xcodeproj::Project::Object::PBXGroup) && child.name == name }
  unless group
    group = parent.new_group(name)
    puts "Created group: #{name}"
  end
  group
end

# Add each file
FILES_TO_ADD.each do |file_info|
  file_path = file_info[:path]
  group_path = file_info[:group_path]
  
  # Check if file exists
  unless File.exist?(file_path)
    puts "Warning: File not found: #{file_path}"
    next
  end
  
  # Navigate to the correct group
  current_group = project.main_group
  group_path.each do |group_name|
    current_group = find_or_create_group(current_group, group_name)
  end
  
  # Check if file already exists in the group
  file_name = File.basename(file_path)
  existing_file = current_group.files.find { |f| f.display_name == file_name }
  
  if existing_file
    puts "File already exists: #{file_path}"
  else
    # Add file reference
    file_ref = current_group.new_file(file_path)
    
    # Add to target
    target.add_file_references([file_ref])
    
    puts "Added file: #{file_path}"
  end
end

# Save the project
project.save
puts "Project saved successfully!"