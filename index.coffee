class Shader
  constructor: (@gl, vertexShader, fragmentShader) ->
    gl = @gl
    @program = gl.createProgram()
    gl.attachShader(program, @compile(vertexShader, gl.VERTEX_SHADER))
    gl.attachShader(program, @compile(fragmentShader, gl.FRAGMENT_SHADER))
    gl.linkProgram(program)

  compile: (script, type) ->
    gl = @gl
    shader = gl.createShader(type)
    gl.shaderSource(shader, script)
    gl.compileShader(shader)

    if !gl.getShaderParameter(shader, gl.COMPILE_STATUS)
      console.warn(gl.getShaderInfoLog(shader))

    shader

  use: ->
    @gl.useProgram(@program)

class NormalShader
  constructor: (gl) ->
    vertexShader = """
      attribute vec2 aVertexCoord;
      attribute vec2 aTextureCoord;
      varying vec2 vTextureCoord;

      void main(void) {
        gl_Position = vec4(aVertexCoord, 0.0, 1.0);
        vTextureCoord = aTextureCoord;
      }
    """
    fragmentShader = """
      precision mediump float;
      uniform sampler2D uTexture;
      varying highp vec2 vTextureCoord;

      void main(void) {
        gl_FragColor = texture2D(uTexture, vTextureCoord);
      }
    """
    super(gl, vertexShader, fragmentShader)


    @uTexture = gl.getUniformLocation(program, "uTexture")
    @aVertexCoord = gl.getAttribLocation(program, "aVertexCoord")
    @aTextureCoord = gl.getAttribLocation(program, "aTextureCoord")
    gl.enableVertexAttribArray(@aVertexCoord)
    gl.enableVertexAttribArray(@aTextureCoord)


class BlurShader
  constructor: (gl) ->
    vertexShader = """
      attribute vec2 aVertexCoord;
      attribute vec2 aTextureCoord;
      varying vec2 vTextureCoord;

      void main(void) {
        gl_Position = vec4(aVertexCoord, 0.0, 1.0);
        vTextureCoord = aTextureCoord;
      }
    """
    fragmentShader = """
      precision mediump float;
      #define RADIUS 20
      uniform sampler2D uTexture;
      uniform vec2 uTextureSize;
      uniform vec2 uTextureSizeInv;
      uniform float uWeights[RADIUS + 1];
      uniform bool uIsHorizontal;
      varying highp vec2 vTextureCoord;

      void main(void) {
        vec2 centerPos = vTextureCoord * uTextureSize;
        vec4 result = vec4(0);

        if (uIsHorizontal) {
          vec2 base = centerPos - vec2(float(RADIUS / 2), 0.0);
          for (int i = 0; i <= RADIUS; ++i) {
            var pos = base + vec2(float(i), 0.0);
            result += texture2D(uTexture, pos * uTextureSizeInv) * uWeights[i];
          }
        } else {
          vec2 base = centerPos - vec2(0.0, float(RADIUS / 2));
          for (int i = 0; i < RADIUS; ++i) {
            var pos = base + vec2(0.0, float(i));
            result += texture2D(uTexture, pos * uTextureSizeInv) * uWeights[i];
          }
        }
        gl_FragColor = result;
      }
    """
    super(gl, vertexShader, fragmentShader)

    @uTexture = gl.getUniformLocation(program, "uTexture")
    @uTextureSize = gl.getUniformLocation(program, "uTextureSize")
    @uTextureSizeInv = gl.getUniformLocation(program, "uTextureSizeInv")
    @uWeights = gl.getUniformLocation(program, "uWeights")
    @aVertexCoord = gl.getAttribLocation(program, "aVertexCoord")
    @aTextureCoord = gl.getAttribLocation(program, "aTextureCoord")

    # 2 * gamma = radius ( = 20)
    radius = 20
    weights = for i in [0..radius]
      r = radius * 0.5
      r2 = r * r
      x = i - r
      1 / Math.sqrt(2 * Math.PI * r2) * Math.exp(-(x * x * 0.5 / r2))

    gl.uniform1fv(@uWeights,new Float32Array(weights))

class FeatureVideoView

  constructor: (@videoElement) ->
    @element = document.createElement('canvas')
    gl = @gl = @element.getContext('webgl')
    unless gl
      return

    @shader = new NormalShader(gl)

    gl.clearColor(0,0,0,1)

    @videoRectBuffer = gl.createBuffer()
    @videoTexture = @createTexture(@videoElement)

    onResize = =>
      @resize window.innerWidth, @videoElement.videoHeight

    window.addEventListener 'resize', onResize
    onResize()

  createTexture: (elem) ->
    gl = @gl
    texture = gl.createTexture()
    gl.bindTexture(gl.TEXTURE_2D, texture)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    texture

  updateTexture: (texture, elem) ->
    gl = @gl
    gl.bindTexture(gl.TEXTURE_2D, texture)
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true)
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, elem)

  resize: (@width, @height) ->
    gl = @gl
    @element.width = @width
    @element.height = @height
    gl.viewport(0, 0, @width, @height)

    {videoWidth, videoHeight} = @videoElement
    widthRatio = videoWidth / @width

    videoRectData = [
      widthRatio, -1
      1, 0
      widthRatio, 1
      1, 1
      -widthRatio, -1,
      0, 0
      -widthRatio, 1,
      0, 1
    ]
    gl.bindBuffer(gl.ARRAY_BUFFER, @videoRectBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(videoRectData), gl.STATIC_DRAW)

  render: ->
    gl = @gl
    @shader.use()
    @updateTexture(@videoTexture, @videoElement)
    gl.bindBuffer(gl.ARRAY_BUFFER, @videoRectBuffer)

    gl.activeTexture(gl.TEXTURE0)
    gl.bindTexture(gl.TEXTURE_2D, @videoTexture)
    gl.uniform1i(@shader.uTexture, 0)

    gl.vertexAttribPointer(@shader.aVertexCoord, 2, gl.FLOAT, false, 4 * 4, 0)
    gl.vertexAttribPointer(@shader.aTextureCoord, 2, gl.FLOAT, false, 4 * 4, 4 * 2)

    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4)

document.addEventListener 'DOMContentLoaded', ->
  video.addEventListener 'loadeddata', ->
    video = document.getElementById('video')
    view =  new FeatureVideoView(video)
    document.body.appendChild(view.element)

    nextFrame = ->
      view.render()
      requestAnimationFrame nextFrame
    nextFrame()
  video.play()
