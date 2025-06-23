#!/usr/bin/env python3
"""
Xcode Project File Updater for VoiceControl

This script automatically adds new Swift files to the Xcode project configuration.
It handles the complex task of updating project.pbxproj with proper UUIDs and references.

Usage:
    python3 add_files_simple.py

The script will:
1. Scan for new Swift files not already in the project
2. Generate unique UUIDs for each file
3. Update the project.pbxproj with proper references
4. Maintain the existing project structure
"""

import os
import re
import uuid
import json
from pathlib import Path

class XcodeProjectUpdater:
    def __init__(self, project_path="VoiceControl.xcodeproj/project.pbxproj"):
        self.project_path = project_path
        self.project_content = ""
        self.files_to_add = []
        self.existing_files = set()
        
    def generate_uuid(self):
        """Generate a 24-character hex UUID for Xcode"""
        return uuid.uuid4().hex[:24].upper()
    
    def read_project(self):
        """Read the current project file"""
        with open(self.project_path, 'r') as f:
            self.project_content = f.read()
            
    def extract_existing_files(self):
        """Extract currently referenced Swift files from the project"""
        # Find all Swift file references
        swift_pattern = r'path = ([^;]+\.swift);'
        matches = re.findall(swift_pattern, self.project_content)
        
        for match in matches:
            # Remove quotes if present
            filename = match.strip('"')
            self.existing_files.add(filename)
            
    def find_new_swift_files(self):
        """Find Swift files in VoiceControl directory that aren't in the project"""
        voice_control_dir = Path("VoiceControl")
        
        for swift_file in voice_control_dir.rglob("*.swift"):
            relative_path = swift_file.relative_to(voice_control_dir)
            filename = relative_path.name
            
            if filename not in self.existing_files:
                # Determine the group based on directory structure
                parts = relative_path.parts
                if len(parts) > 1:
                    group = parts[0]  # Config, Core, Features, Models, Utils
                else:
                    group = "VoiceControl"
                    
                self.files_to_add.append({
                    'path': str(relative_path),
                    'filename': filename,
                    'group': group,
                    'full_path': str(swift_file)
                })
                
    def update_project(self):
        """Update the project file with new files"""
        if not self.files_to_add:
            print("No new files to add")
            return
            
        # Generate UUIDs for each file
        for file_info in self.files_to_add:
            file_info['file_ref'] = self.generate_uuid()
            file_info['build_ref'] = self.generate_uuid()
            
        # Find insertion points
        build_section_match = re.search(r'/\* End PBXBuildFile section \*/', self.project_content)
        file_ref_section_match = re.search(r'/\* End PBXFileReference section \*/', self.project_content)
        
        if not build_section_match or not file_ref_section_match:
            print("Could not find proper insertion points")
            return
            
        # Create build file entries
        build_entries = []
        for file_info in self.files_to_add:
            entry = f"\t\t{file_info['build_ref']} /* {file_info['filename']} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_info['file_ref']} /* {file_info['filename']} */; }};"
            build_entries.append(entry)
            
        # Create file reference entries
        file_ref_entries = []
        for file_info in self.files_to_add:
            entry = f"\t\t{file_info['file_ref']} /* {file_info['filename']} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_info['filename']}; sourceTree = \"<group>\"; }};"
            file_ref_entries.append(entry)
            
        # Insert build files
        build_insert_pos = build_section_match.start()
        self.project_content = (
            self.project_content[:build_insert_pos] +
            '\n'.join(build_entries) + '\n' +
            self.project_content[build_insert_pos:]
        )
        
        # Update file reference insertion position after build files insertion
        file_ref_section_match = re.search(r'/\* End PBXFileReference section \*/', self.project_content)
        file_ref_insert_pos = file_ref_section_match.start()
        
        # Insert file references
        self.project_content = (
            self.project_content[:file_ref_insert_pos] +
            '\n'.join(file_ref_entries) + '\n' +
            self.project_content[file_ref_insert_pos:]
        )
        
        # Add files to source build phase
        sources_pattern = r'(/\* Sources \*/ = \{[^}]+files = \([^)]+)'
        sources_match = re.search(sources_pattern, self.project_content, re.DOTALL)
        
        if sources_match:
            sources_entries = []
            for file_info in self.files_to_add:
                entry = f"\t\t\t\t{file_info['build_ref']} /* {file_info['filename']} in Sources */,"
                sources_entries.append(entry)
                
            insert_pos = sources_match.end()
            self.project_content = (
                self.project_content[:insert_pos] +
                '\n' + '\n'.join(sources_entries) +
                self.project_content[insert_pos:]
            )
            
        # Add files to appropriate groups
        for group_name in set(f['group'] for f in self.files_to_add):
            self.add_files_to_group(group_name)
            
    def add_files_to_group(self, group_name):
        """Add file references to the appropriate group"""
        group_files = [f for f in self.files_to_add if f['group'] == group_name]
        if not group_files:
            return
            
        # Find the group section
        group_pattern = rf'(path = {group_name};[^}}]+children = \([^)]+)'
        group_match = re.search(group_pattern, self.project_content, re.DOTALL)
        
        if group_match:
            group_entries = []
            for file_info in group_files:
                entry = f"\t\t\t\t{file_info['file_ref']} /* {file_info['filename']} */,"
                group_entries.append(entry)
                
            insert_pos = group_match.end()
            self.project_content = (
                self.project_content[:insert_pos] +
                '\n' + '\n'.join(group_entries) +
                self.project_content[insert_pos:]
            )
            
    def write_project(self):
        """Write the updated project file"""
        with open(self.project_path, 'w') as f:
            f.write(self.project_content)
            
    def run(self):
        """Execute the update process"""
        print("Reading project file...")
        self.read_project()
        
        print("Extracting existing files...")
        self.extract_existing_files()
        
        print("Finding new Swift files...")
        self.find_new_swift_files()
        
        if self.files_to_add:
            print(f"\nFound {len(self.files_to_add)} new files to add:")
            for file_info in self.files_to_add:
                print(f"  - {file_info['path']}")
                
            print("\nUpdating project file...")
            self.update_project()
            
            print("Writing updated project file...")
            self.write_project()
            
            print("\nProject updated successfully!")
            print("\nNext steps:")
            print("1. Open Xcode and verify the files appear correctly")
            print("2. Build the project to ensure everything compiles")
            print("3. If needed, manually adjust file locations in Xcode")
        else:
            print("\nNo new files found to add.")

def main():
    """Main entry point"""
    # Check if we're in the right directory
    if not os.path.exists("VoiceControl.xcodeproj"):
        print("Error: VoiceControl.xcodeproj not found in current directory")
        print("Please run this script from the project root directory")
        return
        
    updater = XcodeProjectUpdater()
    updater.run()

if __name__ == "__main__":
    main()