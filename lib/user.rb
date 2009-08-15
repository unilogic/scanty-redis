require 'digest/sha1'

class User
  def self.attrs
		[ :id, :login, :fname, :lname, :email, :password, :password_confirmation, :created_at, :salt ]
	end

	def attrs
		self.class.attrs.inject({}) do |a, key|
			a[key] = send(key)
			a
		end
	end

	attr_accessor *attrs

	def initialize(params={})
		params.each do |key, value|
			send("#{key}=", value)
		end
	end
  
  def created_at=(t)
		@created_at = t.is_a?(Time) ? t : Time.parse(t)
	end
	
  def self.new_from_json(json)
		return nil unless json
		new JSON.parse(json)
	end
  
  def self.db_key_for_uid(id)
		"#{self}:uid:#{id}"
	end
  
  def self.db_key_for_login(login)
		"#{self}:login:#{login}"
	end
	
	def db_key_uid
		self.class.db_key_for_uid(id)
	end
  
  def db_key_login
		self.class.db_key_for_login(login)
	end
	
	def self.global_users_key
		"#{self}:global_users"
	end
  
  def validate
    if self.password != self.password_confirmation
      return false
    end
    
    if DB[self.class.db_key_for_login(login)]
      return false
    end
    
    return true
  end
  
  #### CREATE ####
  def save
    save_attrs = attrs.dup
    save_attrs.delete(:password_confirmation)
		DB[db_key_uid] = save_attrs.to_json
		DB[db_key_login] = id
	end
	
	def add_global
    unless DB.set_member? self.class.global_users_key, "#{self.id}|#{self.login}"
      DB.set_add self.class.global_users_key, "#{self.id}|#{self.login}"
    end
  end
  
	def self.create(params)
		user = new(params)
		
		unless user.validate
		  return nil
		end
		
		unless user.encrypt_password
		  return nil
		end
		
		unless user.id
		  user.id = DB.incr('global:user_counter')
		end
		
		user.save
		user.add_global
		user
	end
  
  def update
    if self.password == self.password_confirmation
      unless self.encrypt_password
  		  return nil
  		end
    end
		
		unless self.save
		  return nil
		end
		self
  end
  
  #### SEARCH ####
  def self.all
    users = DB.set_members(self.global_users_key)
    userArray = []
    users.each { |user|
      userObj = self.new
      userObj.id, userObj.login = user.split('|')
      userArray.push(userObj)
    }
    return userArray
  end
  def self.find_by_login(login)
    id = DB[self.db_key_for_login(login)]
    self.find_by_id(id)
  end
  
  def self.find_by_id(id)
    new_from_json DB[self.db_key_for_uid(id)]
  end
  
  #### DELETE ####
  def self.destroy(id)
    begin
      if user = self.find_by_id(id)
        DB.delete self.db_key_for_uid(id)
        DB.delete self.db_key_for_login(user.login)
        DB.set_delete self.global_users_key, "#{id}|#{user.login}"
      end
    rescue NameError
      nil
    end
  end
  
  def self.destroy_all
    users = self.all
    users.each do |user|
      self.destroy(user.id)
    end
  end
  
  #### AUTH ####
  
  # Authenticates a user by their login name and unencrypted password.  Returns the user or nil.
  def self.authenticate(login, passwd)
    u = find_by_login(login) # need to get the salt
    u && u.authenticated?(passwd) ? u : nil
  end

  # Encrypts some data with the salt.
  def self.encrypt(passwd, salt)
    Digest::SHA512.hexdigest("--#{salt}--#{passwd}--")
  end

  # Encrypts the password with the user salt
  def encrypt(passwd)
    self.class.encrypt(passwd, salt)
  end

  def authenticated?(passwd)
    password == encrypt(passwd)
  end

  def encrypt_password
    return unless password
    self.salt = Digest::SHA512.hexdigest("--#{Time.now.to_s}--#{login}--")
    self.password = encrypt(password)
  end
  
end