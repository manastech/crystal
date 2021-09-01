#! /usr/bin/env crystal

# This helper queries merged pull requests for a given milestone from the GitHub API
# and creates formatted changelog entries.
#
# Pull requests that are already referenced in CHANGELOG.md are omitted, which
# makes it easy to incrementally add entries.
#
# Entries are grouped by topic (based on topic labels) and ordered by date.
# Some annotations are automatically added based on labels.
#
# Usage:
#
#   scripts/github-changelog.cr <milestone>
#
# Environment variables:
#
# * GITHUB_TOKEN: Access token for GitHub API (required)
require "http/client"
require "json"

api_token = ENV["GITHUB_TOKEN"]
repository = "crystal-lang/crystal"
milestone = ARGV.first

query = <<-GRAPHQL
  query($milestone: String) {
    repository(owner: $owner, name: $repository) {
      milestones(query: $milestone, first: 1) {
        nodes {
          pullRequests(first: 300) {
            nodes {
              number
              title
              mergedAt
              permalink
              author {
                login
              }
              labels(first: 10) {
              nodes {
                name
              }
              }
            }
          }
        }
      }
    }
  }
  GRAPHQL

owner, _, name = repository.partition("/")
variables = {
  owner: owner,
  repository: name,
  milestone: milestone,
}

response = HTTP::Client.post("https://api.github.com/graphql", body: {query: query, variables: variables}.to_json, headers: HTTP::Headers{"Authorization" => "bearer #{api_token}"})

module LabelNameConverter
  def self.from_json(pull : JSON::PullParser)
    pull.on_key! "name" do
      String.new(pull)
    end
  end
end

record PullRequest,
  number : Int32,
  title : String,
  mergedAt : Time?,
  permalink : String,
  author : String?,
  labels : Array(String) do
  include JSON::Serializable
  include Comparable(self)

  @[JSON::Field(root: "login")]
  @author : String?

  @[JSON::Field(root: "nodes", converter: JSON::ArrayConverter(LabelNameConverter))]
  @labels : Array(String)

  def to_s(io : IO)
    if labels.includes?("breaking-change")
      io << "**(breaking-change)** "
    end
    if labels.includes?("security")
      io << "**(security)** "
    end
    if labels.includes?("performance")
      io << "**(performance)** "
    end
    io << title << " ("
    io << "[#" << number << "](" << permalink << ")"
    if author = self.author
      io << ", thanks @" << author
    end
    io << ")"
  end

  def <=>(other : self)
    return -1 if labels.includes?("breaking-change") && !other.labels.includes?("breaking-change")
    return -1 if labels.includes?("security") && !other.labels.includes?("security")
    return -1 if labels.includes?("performance") && !other.labels.includes?("performance")
    0
  end
end

parser = JSON::PullParser.new(response.body)
array = parser.on_key! "data" do
  parser.on_key! "repository" do
    parser.on_key! "milestones" do
      parser.on_key! "nodes" do
        parser.read_begin_array
        a = parser.on_key! "pullRequests" do
          parser.on_key! "nodes" do
            Array(PullRequest).new(parser)
          end
        end
        parser.read_end_array
        a
      end
    end
  end
end

changelog = File.read("CHANGELOG.md")
array.select! { |pr| pr.mergedAt && !changelog.index(pr.permalink) }
sections = array.group_by { |pr|
  case pr.labels
  when .any? &.starts_with?("topic:lang")
    "Language"
  when .any? &.starts_with?("topic:compiler")
    "Compiler"
  when .any? &.starts_with?("topic:tools")
    "Tools"
  when .any? &.starts_with?("topic:stdlib")
    "Standard Library"
  else
    "Other"
  end
}

sections.each do |name, prs|
  puts "## #{name}"
  puts
  prs.sort!
  prs.each do |pr|
    puts "- #{pr}"
  end
  puts
end
