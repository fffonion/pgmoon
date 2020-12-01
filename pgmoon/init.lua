local socket = require("pgmoon.socket")
local insert
insert = table.insert
local rshift, lshift, band, bxor
do
  local _obj_0 = require("pgmoon.bit")
  rshift, lshift, band = _obj_0.rshift, _obj_0.lshift, _obj_0.band
  bxor = _obj_0.bxor
end
local pl_file
local ssl
if ngx then
  pl_file = require("pl.file")
  ssl = require("ngx.ssl")
end
local unpack = table.unpack or unpack
local VERSION = "1.12.0"
local _len
_len = function(thing, t)
  if t == nil then
    t = type(thing)
  end
  local _exp_0 = t
  if "string" == _exp_0 then
    return #thing
  elseif "table" == _exp_0 then
    local l = 0
    for _index_0 = 1, #thing do
      local inner = thing[_index_0]
      local inner_t = type(inner)
      if inner_t == "string" then
        l = l + #inner
      else
        l = l + _len(inner, inner_t)
      end
    end
    return l
  else
    return error("don't know how to calculate length of " .. tostring(t))
  end
end
local _debug_msg
_debug_msg = function(str)
  return require("moon").dump((function()
    local _accum_0 = { }
    local _len_0 = 1
    for p in str:gmatch("[^%z]+") do
      _accum_0[_len_0] = p
      _len_0 = _len_0 + 1
    end
    return _accum_0
  end)())
end
local flipped
flipped = function(t)
  local keys
  do
    local _accum_0 = { }
    local _len_0 = 1
    for k in pairs(t) do
      _accum_0[_len_0] = k
      _len_0 = _len_0 + 1
    end
    keys = _accum_0
  end
  for _index_0 = 1, #keys do
    local key = keys[_index_0]
    t[t[key]] = key
  end
  return t
end
local MSG_TYPE = flipped({
  status = "S",
  auth = "R",
  backend_key = "K",
  ready_for_query = "Z",
  query = "Q",
  notice = "N",
  notification = "A",
  password = "p",
  row_description = "T",
  data_row = "D",
  command_complete = "C",
  error = "E"
})
local ERROR_TYPES = flipped({
  severity = "S",
  code = "C",
  message = "M",
  position = "P",
  detail = "D",
  schema = "s",
  table = "t",
  constraint = "n"
})
local PG_TYPES = {
  [16] = "boolean",
  [17] = "bytea",
  [20] = "number",
  [21] = "number",
  [23] = "number",
  [700] = "number",
  [701] = "number",
  [1700] = "number",
  [114] = "json",
  [3802] = "json",
  [1000] = "array_boolean",
  [1005] = "array_number",
  [1007] = "array_number",
  [1016] = "array_number",
  [1021] = "array_number",
  [1022] = "array_number",
  [1231] = "array_number",
  [1009] = "array_string",
  [1015] = "array_string",
  [1002] = "array_string",
  [1014] = "array_string",
  [2951] = "array_string",
  [199] = "array_json",
  [3807] = "array_json"
}
local NULL = "\0"
local tobool
tobool = function(str)
  return str == "t"
end
local Postgres
do
  local _class_0
  local _base_0 = {
    convert_null = false,
    NULL = {
      "NULL"
    },
    PG_TYPES = PG_TYPES,
    user = "postgres",
    host = "127.0.0.1",
    port = "5432",
    ssl = false,
    type_deserializers = {
      json = function(self, val, name)
        local decode_json
        decode_json = require("pgmoon.json").decode_json
        return decode_json(val)
      end,
      bytea = function(self, val, name)
        return self:decode_bytea(val)
      end,
      array_boolean = function(self, val, name)
        local decode_array
        decode_array = require("pgmoon.arrays").decode_array
        return decode_array(val, tobool)
      end,
      array_number = function(self, val, name)
        local decode_array
        decode_array = require("pgmoon.arrays").decode_array
        return decode_array(val, tonumber)
      end,
      array_string = function(self, val, name)
        local decode_array
        decode_array = require("pgmoon.arrays").decode_array
        return decode_array(val)
      end,
      array_json = function(self, val, name)
        local decode_array
        decode_array = require("pgmoon.arrays").decode_array
        local decode_json
        decode_json = require("pgmoon.json").decode_json
        return decode_array(val, decode_json)
      end,
      hstore = function(self, val, name)
        local decode_hstore
        decode_hstore = require("pgmoon.hstore").decode_hstore
        return decode_hstore(val)
      end
    },
    set_type_oid = function(self, oid, name)
      if not (rawget(self, "PG_TYPES")) then
        do
          local _tbl_0 = { }
          for k, v in pairs(self.PG_TYPES) do
            _tbl_0[k] = v
          end
          self.PG_TYPES = _tbl_0
        end
      end
      self.PG_TYPES[assert(tonumber(oid))] = name
    end,
    setup_hstore = function(self)
      local res = unpack(self:query("SELECT oid FROM pg_type WHERE typname = 'hstore'"))
      assert(res, "hstore oid not found")
      return self:set_type_oid(tonumber(res.oid), "hstore")
    end,
    connect = function(self)
      local opts
      if self.sock_type == "nginx" then
        opts = {
          pool = self.pool_name or tostring(self.host) .. ":" .. tostring(self.port) .. ":" .. tostring(self.database) .. ":" .. tostring(self.user)
        }
      end
      local ok, err = self.sock:connect(self.host, self.port, opts)
      if not (ok) then
        return nil, err
      end
      if self.sock:getreusedtimes() == 0 then
        if self.ssl then
          local success
          success, err = self:send_ssl_message()
          if not (success) then
            return nil, err
          end
        end
        local success
        success, err = self:send_startup_message()
        if not (success) then
          return nil, err
        end
        success, err = self:auth()
        if not (success) then
          return nil, err
        end
        success, err = self:wait_until_ready()
        if not (success) then
          return nil, err
        end
      end
      return true
    end,
    settimeout = function(self, ...)
      return self.sock:settimeout(...)
    end,
    disconnect = function(self)
      local sock = self.sock
      self.sock = nil
      return sock:close()
    end,
    keepalive = function(self, ...)
      local sock = self.sock
      self.sock = nil
      return sock:setkeepalive(...)
    end,
    auth = function(self)
      local t, msg = self:receive_message()
      if not (t) then
        return nil, msg
      end
      if not (MSG_TYPE.auth == t) then
        self:disconnect()
        if MSG_TYPE.error == t then
          return nil, self:parse_error(msg)
        end
        error("unexpected message during auth: " .. tostring(t))
      end
      local auth_type = self:decode_int(msg, 4)
      local _exp_0 = auth_type
      if 0 == _exp_0 then
        return true
      elseif 3 == _exp_0 then
        return self:cleartext_auth(msg)
      elseif 5 == _exp_0 then
        return self:md5_auth(msg)
      elseif 10 == _exp_0 then
        return self:scram_sha_256_auth(msg)
      else
        return error("don't know how to auth: " .. tostring(auth_type))
      end
    end,
    cleartext_auth = function(self, msg)
      assert(self.password, "missing password, required for connect")
      self:send_message(MSG_TYPE.password, {
        self.password,
        NULL
      })
      return self:check_auth()
    end,
    md5_auth = function(self, msg)
      local md5
      md5 = require("pgmoon.crypto").md5
      local salt = msg:sub(5, 8)
      assert(self.password, "missing password, required for connect")
      self:send_message(MSG_TYPE.password, {
        "md5",
        md5(md5(self.password .. self.user) .. salt),
        NULL
      })
      return self:check_auth()
    end,
    scram_sha_256_auth = function(self, msg)
      assert(self.password, "missing password, required for connect")

      local openssl_rand = require("openssl.rand")

      -- '18' is the number set by postgres on the server side
      local rand_bytes, err = openssl_rand.bytes(18)

      if not (rand_bytes) then
        return nil, "failed to generate random bytes: " .. tostring(err)
      end

      local c_nonce = ngx.encode_base64(rand_bytes)
      local nonce = "r=" .. c_nonce
      local saslname = ""
      local username = "n=" .. saslname
      local client_first_message_bare = username .. "," .. nonce

      local plus = false
      local bare = false

      if msg:match("SCRAM%-SHA%-256%-PLUS") then
        plus = true
      elseif msg:match("SCRAM%-SHA%-256") then
        bare = true
      else
        return nil, "unsupported SCRAM mechanism name: " .. tostring(msg)
      end

      local gs2_cbind_flag
      local gs2_header
      local cbind_input
      local mechanism_name

      if bare == true then
        gs2_cbind_flag = "n"
        gs2_header = gs2_cbind_flag .. ",,"
        cbind_input = gs2_header
        mechanism_name = "SCRAM-SHA-256" .. NULL
      elseif plus == true then
        local cb_name = "tls-server-end-point"
        gs2_cbind_flag = "p=" .. cb_name
        gs2_header = gs2_cbind_flag .. ",,"
        mechanism_name = "SCRAM-SHA-256-PLUS" .. NULL

        local function be_tls_get_certificate_hash()
          local signature
          local pem

          if self.sock_type == "luasocket" then
            local server_cert = self.sock:getpeercertificate()

            pem = server_cert:pem()

            signature = server_cert:getsignaturename()
          else
            local ssl = require("resty.openssl.ssl").from_socket(self.sock)
            local server_cert = ssl:get_peer_certificate()

            pem = server_cert:to_PEM()

            signature = server_cert:get_signature_name()
          end

          signature = signature:lower()

          if signature:match("md5") or signature:match("sha1") then
            signature = "sha256"
          end

          local openssl_x509 = require("openssl.x509").new(pem, "PEM")

          local openssl_x509_digest, err = openssl_x509:digest(signature, "s")

          if not (openssl_x509_digest) then
            return nil, tostring(err)
          end

          return openssl_x509_digest
        end

        local cbind_data = be_tls_get_certificate_hash()

        cbind_input = gs2_header .. cbind_data
      end

      local client_first_message = gs2_header .. client_first_message_bare

      self:send_message(MSG_TYPE.password, {
        mechanism_name,
        self:encode_int(#client_first_message),
        client_first_message,
      })

      local t, msg = self:receive_message()

      if not (t) then
        return nil, msg
      end

      local server_first_message = msg:sub(5)

      local int32 = self:decode_int(msg, 4)

      if int32 == nil or int32 ~= 11 then
        return nil, "server_first_message error: " .. msg
      end

      local channel_binding = "c=" .. ngx.encode_base64(cbind_input)

      local nonce = server_first_message:match("([^,]+)")

      if not (nonce) then
        return nil, "malformed server message (nonce)"
      end

      local client_final_message_without_proof = channel_binding .. "," .. nonce

      local function hmac(key, str)
        local openssl_hmac = require("openssl.hmac")
        local hmac, err = openssl_hmac.new(key, "sha256")

        if not (hmac) then
          return nil, tostring(err)
        end

        hmac:update(str)

        local final_hmac, err = hmac:final()

        if not (final_hmac) then
          return nil, tostring(err)
        end

        return final_hmac
      end

      local function h(str)
        local openssl_digest, err = require("openssl.digest").new("sha256")

        if not (openssl_digest) then
          return nil, tostring(err)
        end

        openssl_digest:update(str)

        local digest, err = openssl_digest:final()

        if not (digest) then
          return nil, tostring(err)
        end

        return digest
      end

      local function xor(a, b)
        local result = {}

        for i = 1, #a do
          local x = a:byte(i)
          local y = b:byte(i)

          if not (x) or not (y) then
            return
          end

          result[i] = string.char(bxor(x, y))
        end

        return table.concat(result)
      end

      local function hi(str, salt, i)
        local openssl_kdf = require("openssl.kdf")

        salt = ngx.decode_base64(salt)

        local key, err = openssl_kdf.derive({
          type = "PBKDF2",
          md = "sha256",
          salt = salt,
          iter = i,
          pass = str,
          outlen = 32 -- our H() produces a 32 byte hash value (SHA-256)
        })

        if not (key) then
          return nil, "failed to derive pbkdf2 key: " .. tostring(err)
        end

        return key
      end

      local salt = server_first_message:match(",s=([^,]+)")

      if not (salt) then
        return nil, "malformed server message (salt)"
      end

      local i = server_first_message:match(",i=(.+)")

      if not (i) then
        return nil, "malformed server message (iteraton count)"
      end

      if tonumber(i) < 4096 then
        return nil, "the iteration-count sent by the server is less than 4096"
      end

      local salted_password, err = hi(self.password, salt, tonumber(i))

      if not (salted_password) then
        return nil, tostring(err)
      end

      local client_key, err = hmac(salted_password, "Client Key")

      if not (client_key) then
        return nil, tostring(err)
      end

      local stored_key, err = h(client_key)

      if not (stored_key) then
        return nil, tostring(err)
      end

      local auth_message = client_first_message_bare .. "," .. server_first_message .. "," .. client_final_message_without_proof

      local client_signature, err = hmac(stored_key, auth_message)

      if not (client_signature) then
        return nil, tostring(err)
      end

      local proof = xor(client_key, client_signature)

      if not (proof) then
        return nil, "failed to generate the client proof"
      end

      local client_final_message = client_final_message_without_proof .. "," .. "p=" .. ngx.encode_base64(proof)

      self:send_message(MSG_TYPE.password, {
        client_final_message,
      })

      local t, msg = self:receive_message()

      if not (t) then
        return nil, msg
      end

      local server_key, err = hmac(salted_password, "Server Key")

      if not (server_key) then
        return nil, tostring(err)
      end

      local server_signature, err = hmac(server_key, auth_message)

      if not (server_signature) then
        return nil, tostring(err)
      end

      server_signature = ngx.encode_base64(server_signature)

      local sent_server_signature = msg:match("v=([^,]+)")

      if server_signature ~= sent_server_signature then
        return nil, "authentication exchange unsuccessful"
      end

      return self:check_auth()
    end,
    check_auth = function(self)
      local t, msg = self:receive_message()
      if not (t) then
        return nil, msg
      end
      local _exp_0 = t
      if MSG_TYPE.error == _exp_0 then
        return nil, self:parse_error(msg)
      elseif MSG_TYPE.auth == _exp_0 then
        return true
      else
        return error("unknown response from auth")
      end
    end,
    query = function(self, q)
      if q:find(NULL) then
        return nil, "invalid null byte in query"
      end
      self:post(q)
      local row_desc, data_rows, command_complete, err_msg
      local result, notifications
      local num_queries = 0
      while true do
        local t, msg = self:receive_message()
        if not (t) then
          return nil, msg
        end
        local _exp_0 = t
        if MSG_TYPE.data_row == _exp_0 then
          data_rows = data_rows or { }
          insert(data_rows, msg)
        elseif MSG_TYPE.row_description == _exp_0 then
          row_desc = msg
        elseif MSG_TYPE.error == _exp_0 then
          err_msg = msg
        elseif MSG_TYPE.command_complete == _exp_0 then
          command_complete = msg
          local next_result = self:format_query_result(row_desc, data_rows, command_complete)
          num_queries = num_queries + 1
          if num_queries == 1 then
            result = next_result
          elseif num_queries == 2 then
            result = {
              result,
              next_result
            }
          else
            insert(result, next_result)
          end
          row_desc, data_rows, command_complete = nil
        elseif MSG_TYPE.ready_for_query == _exp_0 then
          break
        elseif MSG_TYPE.notification == _exp_0 then
          if not (notifications) then
            notifications = { }
          end
          insert(notifications, self:parse_notification(msg))
        end
      end
      if err_msg then
        return nil, self:parse_error(err_msg), result, num_queries, notifications
      end
      return result, num_queries, notifications
    end,
    post = function(self, q)
      return self:send_message(MSG_TYPE.query, {
        q,
        NULL
      })
    end,
    wait_for_notification = function(self)
      while true do
        local t, msg = self:receive_message()
        if not (t) then
          return nil, msg
        end
        local _exp_0 = t
        if MSG_TYPE.notification == _exp_0 then
          return self:parse_notification(msg)
        end
      end
    end,
    format_query_result = function(self, row_desc, data_rows, command_complete)
      local command, affected_rows
      if command_complete then
        command = command_complete:match("^%w+")
        affected_rows = tonumber(command_complete:match("(%d+)%z$"))
      end
      if row_desc then
        if not (data_rows) then
          return { }
        end
        local fields = self:parse_row_desc(row_desc)
        local num_rows = #data_rows
        for i = 1, num_rows do
          data_rows[i] = self:parse_data_row(data_rows[i], fields)
        end
        if affected_rows and command ~= "SELECT" then
          data_rows.affected_rows = affected_rows
        end
        return data_rows
      end
      if affected_rows then
        return {
          affected_rows = affected_rows
        }
      else
        return true
      end
    end,
    parse_error = function(self, err_msg)
      local severity, message, detail, position
      local error_data = { }
      local offset = 1
      while offset <= #err_msg do
        local t = err_msg:sub(offset, offset)
        local str = err_msg:match("[^%z]+", offset + 1)
        if not (str) then
          break
        end
        offset = offset + (2 + #str)
        do
          local field = ERROR_TYPES[t]
          if field then
            error_data[field] = str
          end
        end
        local _exp_0 = t
        if ERROR_TYPES.severity == _exp_0 then
          severity = str
        elseif ERROR_TYPES.message == _exp_0 then
          message = str
        elseif ERROR_TYPES.position == _exp_0 then
          position = str
        elseif ERROR_TYPES.detail == _exp_0 then
          detail = str
        end
      end
      local msg = tostring(severity) .. ": " .. tostring(message)
      if position then
        msg = tostring(msg) .. " (" .. tostring(position) .. ")"
      end
      if detail then
        msg = tostring(msg) .. "\n" .. tostring(detail)
      end
      return msg, error_data
    end,
    parse_row_desc = function(self, row_desc)
      local num_fields = self:decode_int(row_desc:sub(1, 2))
      local offset = 3
      local fields
      do
        local _accum_0 = { }
        local _len_0 = 1
        for i = 1, num_fields do
          local name = row_desc:match("[^%z]+", offset)
          offset = offset + #name + 1
          local data_type = self:decode_int(row_desc:sub(offset + 6, offset + 6 + 3))
          data_type = self.PG_TYPES[data_type] or "string"
          local format = self:decode_int(row_desc:sub(offset + 16, offset + 16 + 1))
          assert(0 == format, "don't know how to handle format")
          offset = offset + 18
          local _value_0 = {
            name,
            data_type
          }
          _accum_0[_len_0] = _value_0
          _len_0 = _len_0 + 1
        end
        fields = _accum_0
      end
      return fields
    end,
    parse_data_row = function(self, data_row, fields)
      local num_fields = self:decode_int(data_row:sub(1, 2))
      local out = { }
      local offset = 3
      for i = 1, num_fields do
        local _continue_0 = false
        repeat
          local field = fields[i]
          if not (field) then
            _continue_0 = true
            break
          end
          local field_name, field_type
          field_name, field_type = field[1], field[2]
          local len = self:decode_int(data_row:sub(offset, offset + 3))
          offset = offset + 4
          if len < 0 then
            if self.convert_null then
              out[field_name] = self.NULL
            end
            _continue_0 = true
            break
          end
          local value = data_row:sub(offset, offset + len - 1)
          offset = offset + len
          local _exp_0 = field_type
          if "number" == _exp_0 then
            value = tonumber(value)
          elseif "boolean" == _exp_0 then
            value = value == "t"
          elseif "string" == _exp_0 then
            local _ = nil
          else
            do
              local fn = self.type_deserializers[field_type]
              if fn then
                value = fn(self, value, field_type)
              end
            end
          end
          out[field_name] = value
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
      return out
    end,
    parse_notification = function(self, msg)
      local pid = self:decode_int(msg:sub(1, 4))
      local offset = 4
      local channel, payload = msg:match("^([^%z]+)%z([^%z]*)%z$", offset + 1)
      if not (channel) then
        error("parse_notification: failed to parse notification")
      end
      return {
        operation = "notification",
        pid = pid,
        channel = channel,
        payload = payload
      }
    end,
    wait_until_ready = function(self)
      while true do
        local t, msg = self:receive_message()
        if not (t) then
          return nil, msg
        end
        if MSG_TYPE.error == t then
          self:disconnect()
          return nil, self:parse_error(msg)
        end
        if MSG_TYPE.ready_for_query == t then
          break
        end
      end
      return true
    end,
    receive_message = function(self)
      local t, err = self.sock:receive(1)
      if not (t) then
        self:disconnect()
        return nil, "receive_message: failed to get type: " .. tostring(err)
      end
      local len
      len, err = self.sock:receive(4)
      if not (len) then
        self:disconnect()
        return nil, "receive_message: failed to get len: " .. tostring(err)
      end
      len = self:decode_int(len)
      len = len - 4
      local msg = self.sock:receive(len)
      return t, msg
    end,
    send_startup_message = function(self)
      assert(self.user, "missing user for connect")
      assert(self.database, "missing database for connect")
      local data = {
        self:encode_int(196608),
        "user",
        NULL,
        self.user,
        NULL,
        "database",
        NULL,
        self.database,
        NULL,
        "application_name",
        NULL,
        "pgmoon",
        NULL,
        NULL
      }
      return self.sock:send({
        self:encode_int(_len(data) + 4),
        data
      })
    end,
    send_ssl_message = function(self)
      local success, err = self.sock:send({
        self:encode_int(8),
        self:encode_int(80877103)
      })
      if not (success) then
        return nil, err
      end
      local t
      t, err = self.sock:receive(1)
      if not (t) then
        return nil, err
      end
      if t == MSG_TYPE.status then
        if self.sock_type == "nginx" then
          return self.sock:tlshandshake({
            verify = self.ssl_verify,
            client_cert = self.luasec_opts.cert,
            client_priv_key = self.luasec_opts.key
          })
        else
          return self.sock:sslhandshake(self.ssl_verify, self.luasec_opts)
        end
      elseif t == MSG_TYPE.error or self.ssl_required then
        self:disconnect()
        return nil, "the server does not support SSL connections"
      else
        return true
      end
    end,
    send_message = function(self, t, data, len)
      if len == nil then
        len = _len(data)
      end
      len = len + 4
      return self.sock:send({
        t,
        self:encode_int(len),
        data
      })
    end,
    decode_int = function(self, str, bytes)
      if bytes == nil then
        bytes = #str
      end
      local _exp_0 = bytes
      if 4 == _exp_0 then
        local d, c, b, a = str:byte(1, 4)
        return a + lshift(b, 8) + lshift(c, 16) + lshift(d, 24)
      elseif 2 == _exp_0 then
        local b, a = str:byte(1, 2)
        return a + lshift(b, 8)
      else
        return error("don't know how to decode " .. tostring(bytes) .. " byte(s)")
      end
    end,
    encode_int = function(self, n, bytes)
      if bytes == nil then
        bytes = 4
      end
      local _exp_0 = bytes
      if 4 == _exp_0 then
        local a = band(n, 0xff)
        local b = band(rshift(n, 8), 0xff)
        local c = band(rshift(n, 16), 0xff)
        local d = band(rshift(n, 24), 0xff)
        return string.char(d, c, b, a)
      else
        return error("don't know how to encode " .. tostring(bytes) .. " byte(s)")
      end
    end,
    decode_bytea = function(self, str)
      if str:sub(1, 2) == '\\x' then
        return str:sub(3):gsub('..', function(hex)
          return string.char(tonumber(hex, 16))
        end)
      else
        return str:gsub('\\(%d%d%d)', function(oct)
          return string.char(tonumber(oct, 8))
        end)
      end
    end,
    encode_bytea = function(self, str)
      return string.format("E'\\\\x%s'", str:gsub('.', function(byte)
        return string.format('%02x', string.byte(byte))
      end))
    end,
    escape_identifier = function(self, ident)
      return '"' .. (tostring(ident):gsub('"', '""')) .. '"'
    end,
    escape_literal = function(self, val)
      local _exp_0 = type(val)
      if "number" == _exp_0 then
        return tostring(val)
      elseif "string" == _exp_0 then
        return "'" .. tostring((val:gsub("'", "''"))) .. "'"
      elseif "boolean" == _exp_0 then
        return val and "TRUE" or "FALSE"
      end
      return error("don't know how to escape value: " .. tostring(val))
    end,
    __tostring = function(self)
      return "<Postgres socket: " .. tostring(self.sock) .. ">"
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, opts)
      self.sock, self.sock_type = socket.new(opts and opts.socket_type)
      if opts then
        self.user = opts.user
        self.host = opts.host
        self.database = opts.database
        self.port = opts.port
        self.password = opts.password
        self.ssl = opts.ssl
        self.ssl_verify = opts.ssl_verify
        self.ssl_required = opts.ssl_required
        self.pool_name = opts.pool
        local key = opts.key
        local cert = opts.cert
        if self.sock_type == "nginx" and key and cert then
          key = assert(ssl.parse_pem_priv_key(pl_file.read(key, true)))
          cert = assert(ssl.parse_pem_cert(pl_file.read(cert, true)))
        end
        self.luasec_opts = {
          key = key,
          cert = cert,
          cafile = opts.cafile,
          ssl_version = opts.ssl_version or "tlsv1_2"
        }
      end
    end,
    __base = _base_0,
    __name = "Postgres"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Postgres = _class_0
end
return {
  Postgres = Postgres,
  new = Postgres,
  VERSION = VERSION
}
