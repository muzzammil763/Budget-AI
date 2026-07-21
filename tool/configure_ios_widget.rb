# frozen_string_literal: true

require 'xcodeproj'

project_path = File.expand_path('../ios/Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |target| target.name == 'Runner' }
raise 'Runner target not found' unless runner

runner_group = project.main_group.find_subpath('Runner', true)
intents_ref = runner_group.files.find { |file| file.path == 'BudgetAIAppIntents.swift' }
intents_ref ||= runner_group.new_file('BudgetAIAppIntents.swift')
unless runner.source_build_phase.files_references.include?(intents_ref)
  runner.source_build_phase.add_file_reference(intents_ref)
end

runner.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

widget = project.targets.find { |target| target.name == 'BudgetAIWidget' }
unless widget
  widget = project.new_target(:app_extension, 'BudgetAIWidget', :ios, '17.0')
  widget.product_name = 'BudgetAIWidget'
end

widget_group = project.main_group.find_subpath('BudgetAIWidget', true)
widget_group.set_source_tree('<group>')
widget_group.set_path('BudgetAIWidget')
widget_swift = widget_group.files.find { |file| file.path == 'BudgetAIWidget.swift' }
widget_swift ||= widget_group.new_file('BudgetAIWidget.swift')
widget_info = widget_group.files.find { |file| file.path == 'Info.plist' }
widget_info ||= widget_group.new_file('Info.plist')
widget_entitlements = widget_group.files.find do |file|
  file.path == 'BudgetAIWidget.entitlements'
end
widget_entitlements ||= widget_group.new_file('BudgetAIWidget.entitlements')

unless widget.source_build_phase.files_references.include?(widget_swift)
  widget.source_build_phase.add_file_reference(widget_swift)
end

widget.build_configurations.each do |config|
  config.build_settings.merge!(
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'CODE_SIGN_ENTITLEMENTS' => 'BudgetAIWidget/BudgetAIWidget.entitlements',
    'CODE_SIGN_STYLE' => 'Automatic',
    'CURRENT_PROJECT_VERSION' => '$(FLUTTER_BUILD_NUMBER)',
    'DEVELOPMENT_TEAM' => '57F97C6YKT',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'INFOPLIST_FILE' => 'BudgetAIWidget/Info.plist',
    'IPHONEOS_DEPLOYMENT_TARGET' => '17.0',
    'LD_RUNPATH_SEARCH_PATHS' => [
      '$(inherited)',
      '@executable_path/Frameworks',
      '@executable_path/../../Frameworks'
    ],
    'MARKETING_VERSION' => '$(FLUTTER_BUILD_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.muzamil.budget.ai.BudgetAIWidget',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'SKIP_INSTALL' => 'YES',
    'SUPPORTED_PLATFORMS' => 'iphoneos iphonesimulator',
    'SWIFT_VERSION' => '5.0',
    'TARGETED_DEVICE_FAMILY' => '1'
  )
end

runner.add_dependency(widget) unless runner.dependencies.any? do |dependency|
  dependency.target == widget
end

embed_phase = runner.copy_files_build_phases.find do |phase|
  phase.name == 'Embed App Extensions'
end
embed_phase ||= runner.new_copy_files_build_phase('Embed App Extensions')
embed_phase.dst_subfolder_spec = '13'
unless embed_phase.files_references.include?(widget.product_reference)
  build_file = embed_phase.add_file_reference(widget.product_reference, true)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end

# Flutter's Thin Binary script declares the built app Info.plist as an input.
# Keep extension embedding before that script to avoid an Xcode dependency
# cycle between processing Info.plist and copying the .appex bundle.
runner.build_phases.delete(embed_phase)
thin_binary_index = runner.build_phases.index do |phase|
  phase.respond_to?(:name) && phase.name == 'Thin Binary'
end
runner.build_phases.insert(thin_binary_index || runner.build_phases.length, embed_phase)

target_attributes = project.root_object.attributes['TargetAttributes'] ||= {}
[runner, widget].each do |target|
  attributes = target_attributes[target.uuid] ||= {}
  capabilities = attributes['SystemCapabilities'] ||= {}
  capabilities['com.apple.ApplicationGroups.iOS'] = { 'enabled' => 1 }
end

project.save
