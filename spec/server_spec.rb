require 'spec_helper'
require 'server'

module GithubNotificationProxy
describe 'Server' do
  let(:app) { Server.new }

  context 'payload post' do
    it 'returns 200 if save is successful' do
      post 'jira-proxy/1/sync'
      expect(last_response).to be_ok
    end

    it 'returns 500 if save is unsuccessful' do
      allow_any_instance_of(Notification).to receive(:save).and_return(false)
      post 'jira-proxy/1/sync'
      expect(last_response).to be_server_error
    end

    it 'saves handler' do
      post '/jira-proxy/1/sync'
      expect(Notification.last.handler).to eq('jira-proxy')
    end

    it 'saves path' do
      post '/jira-proxy/1/sync'
      expect(Notification.last.path).to eq('1/sync')
    end

    it 'saves path with query string' do
      post '/camci/notifyCommit?foo/bar'
      expect(Notification.last.path).to eq('notifyCommit?foo/bar')
    end

    it 'saves content type' do
      post '/jira-proxy/1/sync', {}, {'CONTENT_TYPE' => 'text/bar'}
      expect(Notification.last.content_type).to eq('text/bar')
    end

    it 'saves payload' do
      post '/jira-proxy/1/sync', {}, {input: 'foo'}
      expect(Notification.last.payload).to eq('foo')
    end

    it 'saves received_at' do
      post '/jira-proxy/1/sync'
      expect(Notification.last.received_at.to_s).to eq(Time.now.to_s)
    end
  end

  context 'retrieve' do
    it 'returns empty array if no new notifications' do
      get '/retrieve'
      expect(last_response).to be_ok
      data = JSON.parse(last_response.body)
      expect(data).to be_empty
    end

    it 'returns JSON encoded notifications' do
      Notification.create(handler: 'foo', path: 'bar/baz', payload: '{"key": "val"}', received_at: Time.now - 5)
      Notification.create(handler: 'foo', path: 'bar/baz', payload: '{"key": "val"}', received_at: Time.now - 4)
      get '/retrieve'
      expect(last_response).to be_ok
      data = JSON.parse(last_response.body)
      expect(data.size).to eq(2)
      expect(data[0]).to include('handler', 'path', 'payload')
    end

    it 'returns notifications in order' do
      Notification.create(handler: 'foo2', path: 'bar/baz', payload: '{"key": "val"}', received_at: Time.now - 4)
      Notification.create(handler: 'foo1', path: 'bar/baz', payload: '{"key": "val"}', received_at: Time.now - 5)
      get '/retrieve'
      data = JSON.parse(last_response.body)
      expect(data.map {|d| d['handler']}).to eq(%w(foo1 foo2))
    end
  end
end
end
