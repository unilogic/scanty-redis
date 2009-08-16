require 'rubygems'
require 'sinatra'

require File.dirname(__FILE__) + '/lib/all'

configure do
	Blog = OpenStruct.new(
		:title => ENV['TITLE'] || 'a scanty blog on redis',
		:author => ENV['AUTHOR'] || 'John Doe',
		:url_base => ENV['URL_BASE'] || 'http://localhost:4567/',
		:admin_password => ENV['ADMIN_PASSWORD'] || 'changeme',
		:admin_cookie_key => 'scanty_admin',
		:admin_cookie_value => ENV['ADMIN_COOKIE_VALUE'] || '51d6d976913ace58',
		:disqus_shortname => 'test'
	)
end

error do
	e = request.env['sinatra.error']
	puts e.to_s
	puts e.backtrace.join("\n")
	"Application error"
end

helpers do
	def admin?
		request.cookies[Blog.admin_cookie_key] == Blog.admin_cookie_value
	end

	def auth
		stop [ 401, 'Not authorized' ] unless admin?
	end

	def cache_page(seconds=5*60)
		response['Cache-Control'] = "public, max-age=#{seconds}" unless development?
	end
	
	def load_json(json)
	  JSON.parse(json)
	end
	
end

layout 'layout'

### Public

get '/' do
	cache_page
	posts = Post.find_range(0, 10)
	erb :index, :locals => { :posts => posts }
end

get '/past/:year/:month/:day/:slug/' do
	cache_page
	post = Post.find_by_slug(params[:slug])
	stop [ 404, "Page not found" ] unless post
	@title = post.title
	erb :post, :locals => { :post => post }
end

get '/past/:year/:month/:day/:slug' do
	cache_page
	redirect "/past/#{params[:year]}/#{params[:month]}/#{params[:day]}/#{params[:slug]}/", 301
end

get '/past' do
	cache_page
	posts = Post.all
	@title = "Archive"
	erb :archive, :locals => { :posts => posts }
end

get '/past/tags/:tag' do
	cache_page
	tag = params[:tag].downcase.strip
	posts = Post.find_tagged(tag)
	@title = "Posts tagged #{tag}"
	erb :tagged, :locals => { :posts => posts, :tag => tag }
end

get '/feed' do
	cache_page
	@posts = Post.find_range(0, 20)
	content_type 'application/atom+xml', :charset => 'utf-8'
	builder :feed
end

get '/rss' do
	cache_page
	redirect '/feed', 301
end

### Admin

get '/posts/new' do
	auth
	erb :edit, :locals => { :post => Post.new, :url => '/posts' }
end

post '/posts' do
	auth
	post = Post.create(
	  :title => params[:title], 
	  :tags => params[:tags], 
	  :body => params[:body], 
	  :created_at => Time.now, 
	  :slug => Post.make_slug(params[:title]),
	  :author => request.cookies['user']
	)
	redirect post.url
end

get '/past/:year/:month/:day/:slug/edit' do
	auth
	post = Post.find_by_slug(params[:slug])
	stop [ 404, "Page not found" ] unless post
	erb :edit, :locals => { :post => post, :url => post.url }
end

get '/past/:year/:month/:day/:slug/delete' do
	auth
	post = Post.find_by_slug(params[:slug])
	stop [ 404, "Page not found" ] unless post
	if post.destroy
	  redirect '/'
	else
	  erb :edit, :locals => { :post => post, :url => post.url }
	end
end

post '/past/:year/:month/:day/:slug/' do
	auth
	post = Post.find_by_slug(params[:slug])
	stop [ 404, "Page not found" ] unless post
	post.title = params[:title]
	post.tags = params[:tags]
	post.body = params[:body]
	post.save
	redirect post.url
end

#### AUTH #####
post '/auth' do
  user = User.find_by_login(params[:login])
  if user && user.authenticated?(params[:password])
	  response.set_cookie(Blog.admin_cookie_key, Blog.admin_cookie_value)
	  attrs = user.attrs
	  attrs.delete(:password)
	  attrs.delete(:password_confirmation)
	  attrs.delete(:salt)
	  response.set_cookie('user', attrs.to_json)
	  redirect '/'
	else
	  erb :auth
	end
end

get '/auth' do
	erb :auth
end

get '/user/:id' do
  auth
  user = User.find_by_id(params[:id])
  stop [ 404, "Page not found" ] unless user
  erb :user_edit, :locals => { :user => user, :url => "/user/#{user.id}" }
end

get '/logout' do
  auth
  response.set_cookie(Blog.admin_cookie_key, nil)
  redirect '/'
end

# Update User
post '/user/:id' do
  auth
  user = User.find_by_id(params[:id])
  if user
    user.fname = params[:fname] unless params[:fname].empty?
    user.lname = params[:lname] unless params[:lname].empty?
    user.email = params[:email] unless params[:email].empty?
    user.password = params[:password] unless params[:password].empty?
    user.password_confirmation = params[:password_confirmation] unless params[:password_confirmation].empty?
    if user.update
      redirect "/users"
    else
      erb :user_edit, :locals => { :user => user, :url => "/user/#{user.id}" }
    end
  else
    redirect "/user/#{user.id}"
  end
  
end

get '/users/new' do
	auth
	erb :user_edit, :locals => { :user => User.new, :url => '/user' }
end

post '/authnouser' do
  if params[:password] == Blog.admin_password
    response.set_cookie(Blog.admin_cookie_key, Blog.admin_cookie_value) 
    redirect '/users/new'
  else
    erb :nousers, :locals => {:url => '/authnouser'}
  end
end

get '/users' do

  users = User.all
  
  if users.length > 0
    auth
    erb :users, :locals => { :users => users }
  else
    erb :nousers, :locals => { :url => '/authnouser' }
  end
end

post '/user' do
  auth
  if user = User.create(
    :login => params[:login], 
    :fname => params[:fname], 
    :lname => params[:lname], 
    :email => params[:email], 
    :password => params[:password], 
    :password_confirmation => params[:password_confirmation], 
    :created_at => Time.now
  )
    if request.cookies['user']
      redirect "/user/#{user.id}"
    else
      response.set_cookie(Blog.admin_cookie_key, nil)
      redirect "/auth"
    end 
  else
    erb :user_edit, :locals => { :user => User.new, :url => '/users' }
  end
end

