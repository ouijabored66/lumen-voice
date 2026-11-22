#!/usr/bin/env ruby
# frozen_string_literal: true
# One-off ASC helper for Lumen 1.6.2 resubmit. Never prints keys, tokens, or raw notes.

require "openssl"
require "json"
require "net/http"
require "base64"
require "time"
require "cgi"

API = "https://api.appstoreconnect.apple.com".freeze
APP_ID = "6836863521".freeze
VERSION = "1.6.2".freeze
BUILD_NUMBER = "7".freeze
SUBMISSION_ID = "174132e5-0e7c-44e7-ac34-6faa3e4b07eb".freeze
OUT = (ENV["ASC_REPORT_DIR"] || "asc-report").freeze

def die(message)
  warn message
  exit 1
end

def b64url(data)
  Base64.urlsafe_encode64(data).delete("=")
end

def ecdsa_raw(der)
  seq = OpenSSL::ASN1.decode(der)
  parts = seq.value.map do |item|
    bytes = item.value.to_s(2)
    bytes = bytes[-32, 32] if bytes.bytesize > 32
    bytes.rjust(32, "\x00")
  end
  die("Could not sign the App Store Connect request.") unless parts.size == 2
  parts.join
end

def jwt(key_id, issuer, p8)
  key = OpenSSL::PKey.read(p8)
  now = Time.now.to_i
  header = b64url({ alg: "ES256", kid: key_id, typ: "JWT" }.to_json)
  body = b64url({ iss: issuer, iat: now, exp: now + 1000, aud: "appstoreconnect-v1" }.to_json)
  signing_input = "#{header}.#{body}"
  sig = ecdsa_raw(key.sign(OpenSSL::Digest::SHA256.new, signing_input))
  "#{signing_input}.#{b64url(sig)}"
end

def token_from_env
  key_id = ENV["ASC_KEY_ID"].to_s
  issuer = ENV["ASC_ISSUER_ID"].to_s
  p8 = ENV["ASC_KEY_P8"].to_s
  die("ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_P8 are required.") if key_id.empty? || issuer.empty? || p8.empty?
  jwt(key_id, issuer, p8)
end

def call_api(method, path, token, body = nil, query = nil)
  uri = URI(API + path)
  uri.query = URI.encode_www_form(query) if query
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = case method
            when "POST" then Net::HTTP::Post.new(uri)
            when "PATCH" then Net::HTTP::Patch.new(uri)
            when "DELETE" then Net::HTTP::Delete.new(uri)
            else Net::HTTP::Get.new(uri)
            end
  request["Authorization"] = "Bearer #{token}"
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(body) if body
  response = http.request(request)
  parsed = response.body.to_s.empty? ? {} : (JSON.parse(response.body) rescue {})
  [response.code.to_i, parsed]
end

def error_detail(parsed)
  errs = parsed["errors"] || []
  return "The App Store Connect request failed." if errs.empty?
  errs.map { |e|
    bits = [e["code"], e["title"], e["detail"]].compact
    assoc = e.dig("meta", "associatedErrors")
    if assoc.is_a?(Hash)
      assoc.each do |_k, list|
        Array(list).each do |ae|
          bits << [ae["code"], ae["title"], ae["detail"]].compact.join(" ")
        end
      end
    elsif assoc
      bits << "associated_errors_present"
    end
    bits.join(" — ")
  }.join(" | ")
end

# Redact secrets but keep review setup URLs and the Drive link.
def redact_notes(text)
  s = text.to_s.dup
  s.gsub!(/\bsk-[A-Za-z0-9_\-]{10,}/, "[REDACTED_KEY]")
  s.gsub!(/\bxai-[A-Za-z0-9_\-]{10,}/, "[REDACTED_KEY]")
  s.gsub!(/\bgsk_[A-Za-z0-9_\-]{10,}/, "[REDACTED_KEY]")
  s.gsub!(/\bAIza[A-Za-z0-9_\-]{10,}/, "[REDACTED_KEY]")
  s.gsub!(/\bAKIA[A-Z0-9]{16}\b/, "[REDACTED_KEY]")
  # Common "Key:" / "API key:" / "token:" values (not URLs)
  s.gsub!(/(?i)((?:api[- ]?key|access[- ]?key|secret[- ]?key|review[- ]?key|auth(?:entication)?[- ]?key|token|password|bearer)\s*[:=]\s*)(?!https?:)(\S+)/) do
    "#{$1}[REDACTED_KEY]"
  end
  # JWT-like
  s.gsub!(/\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}/, "[REDACTED_TOKEN]")
  s
end

def write_file(name, content)
  FileUtils.mkdir_p(OUT)
  path = File.join(OUT, name)
  File.write(path, content)
  path
end

require "fileutils"

WIDGET_SECTION = <<~TEXT.rstrip
  How to try Talk from the Home Screen, Control Center, and Apple Watch:

  Home Screen widget: On the iPhone Home Screen, touch and hold an empty area, tap Edit, then Add Widget. Search for Lumen and add the small or medium “Tap to talk” widget. Tap the widget. Lumen opens and starts listening.

  Control Center: Open Control Center, tap the plus button (or Edit Controls), add the Lumen Listen control, then tap it. Lumen opens and starts listening.

  Apple Watch complication: On the watch, touch and hold the watch face, tap Edit, add the Lumen complication, then tap it. Lumen opens and starts listening.

  The Apple Watch app icon now uses a full-bleed warm gold background, with no transparency, so it displays correctly on the watch.
TEXT

def version_for(token)
  code, parsed = call_api("GET", "/v1/apps/#{APP_ID}/appStoreVersions", token, nil, {
    "filter[platform]" => "IOS",
    "filter[versionString]" => VERSION,
    "limit" => "10",
    "include" => "build",
  })
  die("Could not list versions (#{code}). #{error_detail(parsed)}") unless code == 200
  ver = (parsed["data"] || []).first
  die("No App Store version #{VERSION} found.") unless ver
  included = parsed["included"] || []
  attached = included.find { |i| i["type"] == "builds" }
  [ver, attached]
end

def build_for(token)
  code, parsed = call_api("GET", "/v1/builds", token, nil, {
    "filter[app]" => APP_ID,
    "filter[version]" => BUILD_NUMBER,
    "limit" => "20",
    "sort" => "-uploadedDate",
  })
  die("Could not list builds (#{code}). #{error_detail(parsed)}") unless code == 200
  (parsed["data"] || []).find { |b| b.dig("attributes", "version").to_s == BUILD_NUMBER }
end

def review_detail(token, version_id)
  code, parsed = call_api("GET", "/v1/appStoreVersions/#{version_id}/appStoreReviewDetail", token)
  die("Could not read review detail (#{code}). #{error_detail(parsed)}") unless code == 200
  parsed["data"]
end

def notes_inventory(notes)
  {
    "chars" => notes.length,
    "has_cloud_url" => notes.include?("pikadesktop.tail35f686.ts.net"),
    "has_drive_link" => notes.downcase.include?("drive.google.com") || notes.downcase.include?("docs.google.com"),
    "has_custom_cloud" => notes.include?("Custom") && notes.include?("Cloud URL"),
    "has_model" => notes.downcase.include?("model") || notes.downcase.include?("grok"),
    "has_review_key_mention" => notes.downcase.include?("key"),
    "has_screen_recording" => notes.include?("Screen recording") || notes.downcase.include?("video") || notes.downcase.include?("tutorial"),
    "has_home_screen_widget" => notes.include?("Home Screen widget") || notes.include?("Tap to talk"),
    "has_control_center" => notes.include?("Control Center"),
    "has_watch_complication" => notes.downcase.include?("complication"),
    "has_watch_icon" => notes.downcase.include?("watch") && (notes.downcase.include?("icon") || notes.downcase.include?("gold")),
  }
end

def cmd_export(token)
  ver, attached = version_for(token)
  vattr = ver["attributes"] || {}
  detail = review_detail(token, ver["id"])
  notes = detail.dig("attributes", "notes").to_s
  build = build_for(token)
  code, subp = call_api("GET", "/v1/reviewSubmissions/#{SUBMISSION_ID}", token)
  die("Could not read review submission (#{code}). #{error_detail(subp)}") unless code == 200
  sattr = subp.dig("data", "attributes") || {}

  report = {
    "version" => { "id" => ver["id"], "string" => VERSION, "state" => vattr["appStoreState"], "releaseType" => vattr["releaseType"] },
    "attached_build_id" => attached && attached["id"],
    "attached_build_number" => attached && attached.dig("attributes", "version"),
    "attached_build_processing" => attached && attached.dig("attributes", "processingState"),
    "build7_id" => build && build["id"],
    "build7_processing" => build && build.dig("attributes", "processingState"),
    "review_detail_id" => detail["id"],
    "notes_inventory" => notes_inventory(notes),
    "submission" => { "id" => SUBMISSION_ID, "state" => sattr["state"], "platform" => sattr["platform"], "submittedDate" => sattr["submittedDate"] },
  }
  write_file("report.json", JSON.pretty_generate(report))
  write_file("notes-redacted.txt", redact_notes(notes))
  puts "Exported review notes (redacted) and status. notes_chars=#{notes.length} version_state=#{vattr['appStoreState']} submission_state=#{sattr['state']} attached_build=#{attached && attached.dig('attributes', 'version')}"
end

def merge_notes(existing)
  existing = existing.to_s.rstrip
  die("Existing review notes were empty; refusing to overwrite.") if existing.empty?
  unless existing.include?("pikadesktop.tail35f686.ts.net")
    die("Existing notes are missing the Cloud URL; refusing to replace them.")
  end
  if existing.include?("Home Screen widget") && existing.include?("Control Center") && existing.downcase.include?("complication")
    return [existing, false]
  end
  updated = existing + "\n\n" + WIDGET_SECTION + "\n"
  [updated, true]
end

def cmd_apply(token)
  ver, attached = version_for(token)
  vattr = ver["attributes"] || {}
  detail = review_detail(token, ver["id"])
  existing = detail.dig("attributes", "notes").to_s
  updated, changed = merge_notes(existing)
  if changed
    body = {
      data: {
        type: "appStoreReviewDetails",
        id: detail["id"],
        attributes: { notes: updated },
      },
    }
    pcode, presult = call_api("PATCH", "/v1/appStoreReviewDetails/#{detail['id']}", token, body)
    die("Could not update review notes (#{pcode}). #{error_detail(presult)}") unless [200, 204].include?(pcode)
    puts "Updated App Review Information notes (#{existing.length} -> #{updated.length} chars)."
  else
    puts "App Review Information notes already include the widget how-to; left body in place (#{existing.length} chars)."
  end

  # Read back
  detail2 = review_detail(token, ver["id"])
  notes2 = detail2.dig("attributes", "notes").to_s
  unless notes2.include?("pikadesktop.tail35f686.ts.net") && notes2.include?("Home Screen widget") && notes2.include?("Control Center") && notes2.downcase.include?("complication")
    die("Read-back of review notes is missing expected sections.")
  end
  write_file("notes-redacted.txt", redact_notes(notes2))
  write_file("notes-inventory.json", JSON.pretty_generate(notes_inventory(notes2)))

  build = build_for(token)
  die("Build #{BUILD_NUMBER} was not found or is not VALID.") unless build && build.dig("attributes", "processingState") == "VALID"
  if attached && attached["id"] == build["id"]
    puts "Build #{BUILD_NUMBER} is already attached to version #{VERSION}."
  else
    acode, aparsed = call_api("PATCH", "/v1/appStoreVersions/#{ver['id']}/relationships/build", token, { data: { type: "builds", id: build["id"] } })
    die("Could not attach build (#{acode}). #{error_detail(aparsed)}") unless [200, 204].include?(acode)
    puts "Attached build #{BUILD_NUMBER} (#{build['id']}) to version #{VERSION}."
  end

  # Confirm attachment
  _ver2, attached2 = version_for(token)
  die("Build #{BUILD_NUMBER} is not attached after update.") unless attached2 && attached2["id"] == build["id"]

  # Resubmit existing UNRESOLVED_ISSUES submission.
  # First mark rejected items resolved (App Store Connect "Update review"),
  # then PATCH submitted=true ("Resubmit to App Review").
  scode, sparsed = call_api("GET", "/v1/reviewSubmissions/#{SUBMISSION_ID}", token)
  die("Could not read review submission (#{scode}). #{error_detail(sparsed)}") unless scode == 200
  state = sparsed.dig("data", "attributes", "state").to_s
  puts "reviewSubmission #{SUBMISSION_ID} state=#{state}"
  final_state = state
  submitted = false
  resolved_items = 0
  if state == "UNRESOLVED_ISSUES"
    icode, iparsed = call_api("GET", "/v1/reviewSubmissions/#{SUBMISSION_ID}/items", token, nil, {
      "include" => "appStoreVersion",
      "limit" => "50",
    })
    die("Could not list review submission items (#{icode}). #{error_detail(iparsed)}") unless icode == 200
    items = iparsed["data"] || []
    items.each do |item|
      istate = item.dig("attributes", "state").to_s
      puts "reviewSubmissionItem #{item['id']} state=#{istate}"
      next unless istate == "REJECTED"
      body = { data: { type: "reviewSubmissionItems", id: item["id"], attributes: { resolved: true } } }
      rcode, rparsed = call_api("PATCH", "/v1/reviewSubmissionItems/#{item['id']}", token, body)
      die("Could not resolve reviewSubmissionItem #{item['id']} (#{rcode}). #{error_detail(rparsed)}") unless [200, 204].include?(rcode)
      resolved_items += 1
      puts "Marked reviewSubmissionItem #{item['id']} resolved."
    end
    body = { data: { type: "reviewSubmissions", id: SUBMISSION_ID, attributes: { submitted: true } } }
    pcode, presult = call_api("PATCH", "/v1/reviewSubmissions/#{SUBMISSION_ID}", token, body)
    if pcode >= 400
      die("Could not resubmit reviewSubmission (#{pcode}). #{error_detail(presult)}")
    end
    submitted = true
    final_state = presult.dig("data", "attributes", "state").to_s
    puts "Resubmitted reviewSubmission #{SUBMISSION_ID} after resolving #{resolved_items} item(s). new_state=#{final_state.empty? ? 'unknown' : final_state}"
  elsif %w[WAITING_FOR_REVIEW IN_REVIEW].include?(state)
    puts "Submission is already #{state}; not submitting again."
  else
    die("Unexpected reviewSubmission state #{state}; did not submit.")
  end

  # Re-read version and submission
  ver3, attached3 = version_for(token)
  scode2, sparsed2 = call_api("GET", "/v1/reviewSubmissions/#{SUBMISSION_ID}", token)
  sattr2 = (sparsed2["data"] || {})["attributes"] || {}
  report = {
    "notes_updated" => changed,
    "notes_chars_before" => existing.length,
    "notes_chars_after" => notes2.length,
    "notes_inventory" => notes_inventory(notes2),
    "version" => { "id" => ver3["id"], "string" => VERSION, "state" => ver3.dig("attributes", "appStoreState"), "releaseType" => ver3.dig("attributes", "releaseType") },
    "attached_build_id" => attached3 && attached3["id"],
    "attached_build_number" => attached3 && attached3.dig("attributes", "version"),
    "submission" => { "id" => SUBMISSION_ID, "state_before" => state, "state_after" => sattr2["state"], "submitted" => submitted, "resolved_items" => resolved_items, "submittedDate" => sattr2["submittedDate"], "platform" => sattr2["platform"] },
    "resolution_center_reply" => "not_posted_official_api_unsupported",
  }
  write_file("report.json", JSON.pretty_generate(report))
  puts "Done. version_state=#{ver3.dig('attributes', 'appStoreState')} submission_state=#{sattr2['state']} attached_build=#{attached3 && attached3.dig('attributes', 'version')}"
end

cmd = ARGV[0].to_s
token = token_from_env
case cmd
when "export"
  cmd_export(token)
when "apply"
  cmd_apply(token)
else
  die("Usage: asc_resubmit.rb export|apply")
end
