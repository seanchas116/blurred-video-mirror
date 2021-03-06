class Shader
  @::vertexShader = """
    attribute vec2 aVertexCoord;
    attribute vec2 aTextureCoord;
    varying vec2 vTextureCoord;

    void main(void) {
      gl_Position = vec4(aVertexCoord, 0.0, 1.0);
      vTextureCoord = aTextureCoord;
    }
  """
  @::fragmentShader = """
    precision mediump float;
    uniform sampler2D uTexture;
    varying highp vec2 vTextureCoord;

    void main(void) {
      gl_FragColor = texture2D(uTexture, vTextureCoord);
    }
  """

  constructor: (@gl) ->
    gl = @gl
    program = @program = gl.createProgram()
    gl.attachShader(program, @compile(@vertexShader, gl.VERTEX_SHADER))
    gl.attachShader(program, @compile(@fragmentShader, gl.FRAGMENT_SHADER))
    gl.linkProgram(program)

    @uTexture = gl.getUniformLocation(@program, "uTexture")
    @aVertexCoord = gl.getAttribLocation(@program, "aVertexCoord")
    @aTextureCoord = gl.getAttribLocation(@program, "aTextureCoord")
    gl.enableVertexAttribArray(@aVertexCoord)
    gl.enableVertexAttribArray(@aTextureCoord)

  compile: (script, type) ->
    gl = @gl
    shader = gl.createShader(type)
    gl.shaderSource(shader, script)
    gl.compileShader(shader)

    if !gl.getShaderParameter(shader, gl.COMPILE_STATUS)
      console.warn(gl.getShaderInfoLog(shader))

    shader

  setTexture: (texture, index) ->
    @use()
    gl = @gl
    texture.register(index)
    gl.uniform1i(@uTexture, index)

  use: ->
    @gl.useProgram(@program)

class BlurShader extends Shader
  BLUR_RADIUS = 20

  @::fragmentShader = """
    precision mediump float;
    #define RADIUS #{BLUR_RADIUS}
    uniform sampler2D uTexture;
    uniform vec2 uTextureSizeInv;
    uniform float uWeights[2 * RADIUS + 1];
    uniform bool uIsHorizontal;
    varying vec2 vTextureCoord;

    void main(void) {
      vec4 result = vec4(0);
      vec2 orientation = uIsHorizontal ? vec2(1.0, 0.0) : vec2(0.0, 1.0);

      for (int i = -RADIUS; i <= RADIUS; ++i) {
        vec2 pos = vTextureCoord + orientation * float(i) * uTextureSizeInv;
        result += texture2D(uTexture, pos) * uWeights[i];
      }
      gl_FragColor = result;
    }
  """
  constructor: (gl) ->
    super(gl)

    @uTextureSizeInv = gl.getUniformLocation(@program, "uTextureSizeInv")
    @uWeights = gl.getUniformLocation(@program, "uWeights")
    @uIsHorizontal = gl.getUniformLocation(@program, "uIsHorizontal")
    @use()

    # 2 * sigma = radius ( = 20)
    weights = do ->
      s = BLUR_RADIUS * 0.5
      s2 = s * s
      for x in [-BLUR_RADIUS..BLUR_RADIUS]
        1 / Math.sqrt(2 * Math.PI * s2) * Math.exp(-(x * x * 0.5 / s2))

    sum = weights.reduce((x, y) => x + y)
    weights = weights.map((x) => x / sum)

    gl.uniform1fv(@uWeights, new Float32Array(weights))
    @setHorizontal(true)

  setTexture: (texture, index) ->
    super(texture, index)
    gl = @gl
    gl.uniform2f(@uTextureSizeInv, 1 / texture.width, 1 / texture.height)

  setHorizontal: (whether) ->
    @use()
    @gl.uniform1i(@uIsHorizontal, whether)

class Model

  constructor: (@gl, @shader) ->
    gl = @gl
    @buffer = gl.createBuffer()

  update: (data) ->
    @use()
    gl = @gl
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(data), gl.STATIC_DRAW)
    @length = data.length / 4

  use: ->
    gl = @gl
    gl.bindBuffer(gl.ARRAY_BUFFER, @buffer)

  render: ->
    gl = @gl
    @use()
    gl.vertexAttribPointer(@shader.aVertexCoord, 2, gl.FLOAT, false, 4 * 4, 0)
    gl.vertexAttribPointer(@shader.aTextureCoord, 2, gl.FLOAT, false, 4 * 4, 4 * 2)
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, @length)

class Texture

  constructor: (@gl) ->
    gl = @gl
    @texture = gl.createTexture()
    gl.bindTexture(gl.TEXTURE_2D, @texture)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

  empty: (@width, @height) ->
    @use()
    gl = @gl
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, @width, @height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null)

  video: (elem) ->
    @use()
    gl = @gl
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true)
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, elem)
    @width = elem.videoWidth
    @height = elem.videoHeight

  use: ->
    gl = @gl
    gl.bindTexture(gl.TEXTURE_2D, @texture)

  register: (@index) ->
    gl = @gl
    gl.activeTexture(gl.TEXTURE0 + @index)
    @use()

class Framebuffer

  constructor: (@gl) ->
    gl = @gl

    @framebuffer = gl.createFramebuffer()
    @texture = new Texture(gl)

  resize: (width, height) ->
    gl = @gl
    @using =>
      @texture.empty(width, height)
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, @texture.texture, 0)

  using: (f) ->
    gl = @gl
    gl.bindFramebuffer(gl.FRAMEBUFFER, @framebuffer)
    f()
    gl.bindFramebuffer(gl.FRAMEBUFFER, null)

class BlurredVideoMirror

  constructor: (@videoElement) ->
    @element = document.createElement('canvas')
    gl = @gl = @element.getContext 'webgl',
      alpha: false
      depth: false
      stencil: false
      antialias: false
      premultipliedAlpha: true

    @isGLSupported = gl?

    unless @isGLSupported
      return

    @shader = new Shader(gl)
    @blurShader = new BlurShader(gl)

    gl.clearColor(0,0,0,1)

    @videoRect = new Model(gl, @shader)
    @videoTexture = new Texture(gl)
    @framebuffers = [new Framebuffer(gl), new Framebuffer(gl)]
    @framebufferRect = new Model(gl, @blurShader)

    @framebufferRect.update [
      1, -1,
      1, 0,
      1, 1,
      1, 1,
      -1, -1,
      0, 0,
      -1, 1,
      0, 1
    ]

    onResize = =>
      @resize window.innerWidth, @videoElement.videoHeight

    window.addEventListener 'resize', onResize
    onResize()

  resize: (@width, @height) ->
    gl = @gl
    @element.width = @width
    @element.height = @height
    gl.viewport(0, 0, @width, @height)

    {videoWidth, videoHeight} = @videoElement
    heightScale = @height / videoHeight

    @videoRect.update [
      1, -heightScale
      1, 0

      1, heightScale
      1, 1

      -1, -heightScale
      0, 0

      -1, heightScale
      0, 1
    ]

    @framebuffers[0].resize(@width, @height)
    @framebuffers[1].resize(@width, @height)

  render: ->
    gl = @gl
    @videoTexture.video(@videoElement)
    @shader.setTexture(@videoTexture, 0)

    @framebuffers[0].using =>
      @videoRect.render()

    @blurShader.setHorizontal(true)
    @blurShader.setTexture(@framebuffers[0].texture, 1)

    @framebuffers[1].using =>
      @framebufferRect.render()

    @blurShader.setHorizontal(false)
    @blurShader.setTexture(@framebuffers[1].texture, 2)

    @framebufferRect.render()

  nextFrame: ->
    # 30 fps
    if @frameCount % 2 == 0
      @render()
    @frameCount += 1
    requestAnimationFrame =>
      @nextFrame()

  play: ->
    @frameCount = 0
    @nextFrame()

document.addEventListener 'DOMContentLoaded', ->
  video.addEventListener 'loadeddata', ->
    video = document.getElementById('video')
    view =  new BlurredVideoMirror(video)
    document.body.appendChild(view.element)
    view.play()

  video.play()
