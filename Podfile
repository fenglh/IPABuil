

#arch -x86_64 pod install

platform :osx, '11.0'

#use_frameworks!

target 'IPABuild' do
  pod 'xcodeproj', '~> 8.8.0'
  pod 'ASN1Decoder', '~> 1.8.0'
  pod 'KeychainAccess'
  pod 'NMSSH-riden', '~> 2.7.2'

end

post_install do |installer|
      installer.pods_project.targets.each do |target|
          target.build_configurations.each do |config|
          xcconfig_path = config.base_configuration_reference.real_path
          xcconfig = File.read(xcconfig_path)
          xcconfig_mod = xcconfig.gsub(/DT_TOOLCHAIN_DIR/, "TOOLCHAIN_DIR")
          File.open(xcconfig_path, "w") { |file| file << xcconfig_mod }
          end
          
        target.build_configurations.each do |config|
            config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '11.0'
        end
      end
  end
