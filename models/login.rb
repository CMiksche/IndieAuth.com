class Login

  def self.generate_auth_code(params)
    jwt = JWT.encode(params.merge({
      :nonce => Random.rand(100000..999999),
      :created_at => Time.now.to_i,
      :id => "#{Time.now.to_i}.#{Random.rand(10000..99999)}"
    }), SiteConfig.jwt_key)

    salt = SecureRandom.random_bytes(16)
    iv = OpenSSL::Cipher.new('aes-256-gcm').encrypt.random_iv
    encrypted = Encryptor.encrypt(jwt, :key => SiteConfig.jwt_key, :iv => iv, :salt => salt)
    salt64 = Base64.urlsafe_encode64 salt
    iv64 = Base64.urlsafe_encode64 iv
    encrypted64 = Base64.urlsafe_encode64 encrypted

    "#{salt64}.#{encrypted64}.#{iv64}"
  end

  def self.build_redirect_uri(params, response_type='code')
    auth_code = self.generate_auth_code params

    puts "Building redirect for login #{params.inspect}"
    if params[:redirect_uri]
      redirect_uri = URI.parse params[:redirect_uri]
      p = Rack::Utils.parse_query redirect_uri.query
      p[response_type] = auth_code
      p['me'] = params[:me]
      p['state'] = params[:state] if params[:state]
      redirect_uri.query = Rack::Utils.build_query p
      redirect_uri = redirect_uri.to_s
    else
      redirect_uri = "/success?#{response_type}=#{auth_code}"
      redirect_uri = "#{redirect_uri}&state=#{params[:state]}" if params[:state]
    end

    redirect_uri
  end

  def self.decode_auth_code(code)
    begin
      salt64, encrypted64, iv64 = code.split '.'

      encrypted = Base64.urlsafe_decode64 encrypted64
      iv = Base64.urlsafe_decode64 iv64
      salt = Base64.urlsafe_decode64 salt64

      decrypted_code = Encryptor.decrypt(encrypted, :key => SiteConfig.jwt_key, :iv => iv, :salt => salt)

      login = JWT.decode(decrypted_code, SiteConfig.jwt_key)
      login = login.first # new JWT library returns a 2-element array after decoding
    rescue => e
      nil
    end
  end

  def self.used?(login)
    # When a code is used, the ID cached in Redis for 2 minutes. If it's present, it has been used.
    return R.get "indieauth::code::#{login['id']}"
  end

  def self.mark_used(login)
    R.setex "indieauth::code::#{login['id']}", 120, Time.now.to_i
  end

  def self.expired?(login)
    # Auth codes are only valid for 60 seconds
    return login['created_at'] < Time.now.to_i - 60
  end

  def self.generate_token
    SecureRandom.urlsafe_base64(36)
  end

  def self.generate_verification_code
    characters = ('2'..'9').to_a + ('A'..'Z').to_a - %w[I O]
    (0...6).map { characters[SecureRandom.random_number(characters.size)] }.join
  end
end
