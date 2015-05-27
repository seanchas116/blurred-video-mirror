class FeatureVideoView

  constructor: (@videoElement) ->
    @element = document.createElement('canvas')
    gl = @gl = @element.getContext('webgl')
    unless gl
      return

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

    @setupShader vertexShader, fragmentShader
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

  compileShader: (script, type) ->
    gl = @gl
    shader = gl.createShader(type)
    gl.shaderSource(shader, script)
    gl.compileShader(shader)

    if !gl.getShaderParameter(shader, gl.COMPILE_STATUS)
      console.warn(gl.getShaderInfoLog(shader))

    shader

  setupShader: (vertexShader, fragmentShader) ->
    gl = @gl
    program = gl.createProgram()
    gl.attachShader(program, @compileShader(vertexShader, gl.VERTEX_SHADER))
    gl.attachShader(program, @compileShader(fragmentShader, gl.FRAGMENT_SHADER))
    gl.linkProgram(program)
    gl.useProgram(program)

    @uTexture = gl.getUniformLocation(program, "uTexture")
    @aVertexCoord = gl.getAttribLocation(program, "aVertexCoord")
    @aTextureCoord = gl.getAttribLocation(program, "aTextureCoord")
    gl.enableVertexAttribArray(@aVertexCoord)
    gl.enableVertexAttribArray(@aTextureCoord)

  render: ->
    gl = @gl
    @updateTexture(@videoTexture, @videoElement)
    gl.bindBuffer(gl.ARRAY_BUFFER, @videoRectBuffer)

    gl.activeTexture(gl.TEXTURE0)
    gl.bindTexture(gl.TEXTURE_2D, @videoTexture)
    gl.uniform1i(@uTexture, 0)

    gl.vertexAttribPointer(@aVertexCoord, 2, gl.FLOAT, false, 4 * 4, 0)
    gl.vertexAttribPointer(@aTextureCoord, 2, gl.FLOAT, false, 4 * 4, 4 * 2)

    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4)

document.addEventListener 'DOMContentLoaded', ->
  video = document.getElementById('video')
  view =  new FeatureVideoView(video)
  document.body.appendChild(view.element)

  nextFrame = ->
    view.render()
    requestAnimationFrame nextFrame

  video.play()
  nextFrame()
