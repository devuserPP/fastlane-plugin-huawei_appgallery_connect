require 'fastlane_core/ui/ui'
require 'cgi'
require 'json'
require 'net/http'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

  module Helper
    class HuaweiAppgalleryConnectHelper
      # Fetches an access token
      def self.get_token(client_id, client_secret)
        UI.important("Fetching app access token")
        uri = URI('https://connect-api.cloud.huawei.com/api/oauth2/v1/token')
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
        req.body = { client_id: client_id, grant_type: 'client_credentials', client_secret: client_secret }.to_json
        res = http.request(req)
        result_json = JSON.parse(res.body)
        result_json['access_token']
      end

      # Fetches the app ID using the package name
      def self.get_app_id(token, client_id, package_id)
        UI.message("Fetching App ID")
        uri = URI.parse("https://connect-api.cloud.huawei.com/api/publish/v2/appid-list?packageName=#{package_id}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        request = Net::HTTP::Get.new(uri.request_uri)
        request["client_id"] = client_id
        request["Authorization"] = "Bearer #{token}"
        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          UI.user_error!("Cannot obtain app id, check API Token / Permissions (status code: #{response.code})")
        end
        result_json = JSON.parse(response.body)
        if result_json['ret']['code'] == 0
          UI.success("Successfully retrieved app id")
          result_json['appids'][0]['value']
        else
          UI.user_error!("Failed to get app id: #{result_json}")
        end
      end

      # Fetches app information
      def self.get_app_info(token, client_id, app_id)
        UI.message("Fetching App Info")
        uri = URI.parse("https://connect-api.cloud.huawei.com/api/publish/v2/app-info?appId=#{app_id}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        request = Net::HTTP::Get.new(uri.request_uri)
        request["client_id"] = client_id
        request["Authorization"] = "Bearer #{token}"
        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          UI.user_error!("Cannot fetch app info, check API Token / Permissions (status code: #{response.code})")
        end
        result_json = JSON.parse(response.body)
        if result_json['ret']['code'] == 0
          UI.success("Successfully retrieved app info")
          result_json['appInfo']
        else
          UI.user_error!("Failed to fetch app info: #{result_json}")
        end
      end

      def self.update_app_localization_info(token, params)
        metadata_path = params[:metadata_path] || 'fastlane/metadata/huawei'
        UI.important("Uploading app localization information from path: #{metadata_path}")
      
        # Fetch app-info for upload URLs
        app_info_uri = URI.parse("https://connect-api.cloud.huawei.com/api/publish/v2/app-info?appId=#{params[:app_id]}")
        http = Net::HTTP.new(app_info_uri.host, app_info_uri.port)
        http.use_ssl = true
        app_info_request = Net::HTTP::Get.new(app_info_uri.request_uri)
        app_info_request['client_id'] = params[:client_id]
        app_info_request['Authorization'] = "Bearer #{token}"
        app_info_request['Content-Type'] = 'application/json'
      
        app_info_response = http.request(app_info_request)
        unless app_info_response.is_a?(Net::HTTPSuccess)
          UI.user_error!("Cannot fetch app-info (status code: #{app_info_response.code}, body: #{app_info_response.body})")
        end
      
        app_info_result = JSON.parse(app_info_response.body)
        unless app_info_result['ret']['code'] == 0
          UI.user_error!("Failed to fetch app-info: #{app_info_result}")
        end
      
        # Parse localization data
        localization_data = {}
        app_info_result['languages'].each do |lang_data|
          localization_data[lang_data['lang']] = {
            app_icon_url: lang_data.dig('deviceMaterials', 0, 'appIcon'),
            screenshot_urls: lang_data.dig('deviceMaterials', 0, 'screenShots') || []
          }
        end
      
        # Process localization files
        Dir.glob("#{metadata_path}/*") do |folder|
          lang = File.basename(folder)
          next unless localization_data.key?(lang)
      
          UI.important("Processing localization for language: #{lang}")
          uri = URI.parse("https://connect-api.cloud.huawei.com/api/publish/v2/app-language-info?appId=#{params[:app_id]}")
          request = Net::HTTP::Put.new(uri.request_uri)
          request['client_id'] = params[:client_id]
          request['Authorization'] = "Bearer #{token}"
          request['Content-Type'] = 'application/json'
      
          # Prepare request body
          body = { "lang": lang }
          Dir.glob("#{folder}/*") do |file|
            case File.basename(file)
            when 'app_name.txt'
              body[:appName] = File.read(file).strip
            when 'app_description.txt'
              body[:appDesc] = File.read(file).strip
            when 'introduction.txt'
              body[:briefInfo] = File.read(file).strip
            when 'release_notes.txt'
              body[:newFeatures] = File.read(file).strip
            end
          end
      
          # Upload app icon
          app_icon_path = "#{folder}/images/app_icon.png"
          if File.exist?(app_icon_path)
            body[:icon] = upload_asset(app_icon_path, localization_data[lang][:app_icon_url], token)
          else
            UI.message("No app icon found for #{lang}, skipping...")
          end
      
          # Upload screenshots
          screenshots_path = "#{folder}/images/screenshots"
          if Dir.exist?(screenshots_path)
            body[:introPic] ||= []
            Dir.glob("#{screenshots_path}/*.png").each do |screenshot|
              screenshot_url = localization_data[lang][:screenshot_urls].shift
              if screenshot_url
                body[:introPic] << upload_asset(screenshot, screenshot_url, token)
              else
                UI.user_error!("No more screenshot upload URLs for #{lang}")
              end
            end
          else
            UI.message("No screenshots found for #{lang}, skipping...")
          end
      
          # Remove empty fields and upload localization
          body.compact!
          request.body = body.to_json
          response = http.request(request)
      
          unless response.is_a?(Net::HTTPSuccess)
            UI.user_error!("Failed to upload localization for #{lang} (status code: #{response.code}, body: #{response.body})")
          end
      
          result_json = JSON.parse(response.body)
          if result_json['ret']['code'] == 0
            UI.success("Localization updated successfully for #{lang}")
          else
            UI.user_error!("Failed to update localization for #{lang}: #{result_json}")
          end
        end
      end
      
      # Uploads an asset to the given URL
      def self.upload_asset(file_path, upload_url, token)
        UI.message("Uploading asset: #{file_path}")
        uri = URI.parse(upload_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        request = Net::HTTP::Put.new(uri.request_uri)
        request['Content-Type'] = 'application/octet-stream'
        request.body = File.read(file_path)
      
        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          UI.user_error!("Failed to upload asset #{file_path} (status code: #{response.code}, body: #{response.body})")
        end
      
        upload_url
      end
      
      # Upload APK or AAB file
      def self.upload_app(token, client_id, app_id, apk_path, is_aab)
        file_name = is_aab ? 'release.aab' : 'release.apk'
        file_suffix = is_aab ? 'aab' : 'apk'
        file_size = File.size(apk_path)
        sha256 = Digest::SHA256.file(apk_path).hexdigest

        UI.message("Preparing to upload #{file_name}")

        # Step 1: Get Upload URL
        uri = URI("https://connect-api.cloud.huawei.com/api/publish/v2/upload-url/for-obs?appId=#{app_id}&fileName=#{file_name}&contentLength=#{file_size}&suffix=#{file_suffix}")
        response = send_request(uri, method: :get, token: token, client_id: client_id)
        result_json = JSON.parse(response.body)

        upload_url = result_json.dig('urlInfo', 'url')
        headers = result_json.dig('urlInfo', 'headers')

        if upload_url.nil?
          UI.user_error!("Failed to obtain upload URL: #{result_json}")
        end

        # Step 2: Upload File
        UI.important("Uploading #{file_name} to Huawei servers.")
        upload_response = send_request(URI(upload_url), method: :put, headers: headers) do |req|
          req.body = File.read(apk_path)
        end

        unless upload_response.is_a?(Net::HTTPSuccess)
          UI.user_error!("File upload failed: #{upload_response.body}")
        end

        # Step 3: Save File Info
        save_uri = URI("https://connect-api.cloud.huawei.com/api/publish/v2/app-file-info?appId=#{app_id}")
        file_data = {
          fileType: 5,
          files: [{
            fileName: file_name,
            fileDestUrl: result_json.dig('urlInfo', 'objectId')
          }]
        }
        save_response = send_request(save_uri, method: :put, token: token, client_id: client_id, body: file_data)
        save_result = JSON.parse(save_response.body)

        if save_result.dig('ret', 'code') == 0
          UI.success("#{file_name} uploaded and saved successfully.")
        else
          UI.user_error!("Failed to save uploaded file info: #{save_result}")
        end
      end

      # Helper method to send HTTP requests
      def self.send_request(uri, method:, token: nil, client_id: nil, body: nil, headers: {})
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = case method
                  when :get then Net::HTTP::Get.new(uri)
                  when :post then Net::HTTP::Post.new(uri)
                  when :put then Net::HTTP::Put.new(uri)
                  else
                    raise "Unsupported HTTP method: #{method}"
                  end

        request['Content-Type'] = 'application/json'
        request['Authorization'] = "Bearer #{token}" if token
        request['client_id'] = client_id if client_id
        headers.each { |key, value| request[key] = value }
        request.body = body.to_json if body

        http.request(request)
      end
    end
  end
end
