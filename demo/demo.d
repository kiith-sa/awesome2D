//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Awesome2D 2D lighting demo.
module demo.demo;


import std.algorithm;
import std.conv;
import std.math;
import std.stdio;
import std.typecons;

import dgamevfs._;
import gl3n.aabb;

import color;
import demo.camera2d;
import demo.light;
import demo.lightmanager;
import demo.map;
import demo.sprite;
import demo.spriterenderer;
import demo.spritemanager;
import demo.vectorrenderer;
import font.fontrenderer;
import gui.exceptions;
import gui.guisystem;
import math.math;
alias math.math.clamp clamp;
import memory.memory;
import platform.key;
import platform.platform;
import spatial.centeredsquare;
import time.eventcounter;
import time.gametime;
import platform.sdl2platform;
import util.linalg;
import util.yaml;
import video.exceptions;
import video.renderer;
import video.sdl2glrenderer;

/// Exception thrown when Awesome2D fails to start.
class StartupException : Exception 
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Main class of the Awesome2D 2D lighting demo.
class Demo
{
private:
    // Directory to load data and configuration from.
    VFSDir dataDir_;

    // Platform used for user input.
    Platform platform_;
    // Renderer.
    Renderer renderer_;
    // Container managing the renderer and its dependencies.
    RendererContainer rendererContainer_;

    // GUI subsystem.
    GUISystem guiSystem_;
    // If true, the GUI is enabled and drawn.
    bool guiEnabled_ = true;

    // Main config file (YAML).
    YAMLNode config_;
    // Continue running?
    bool continue_ = true;

    // Camera used to view the scene.
    Camera2D camera_;
    // Constructs and manages sprites.
    Sprite3DManager spriteManager_;
    // Renders sprites with lighting.
    Sprite3DRenderer spriteRenderer_;
    // Renders vector sprites on the map.
    VectorRenderer dimetricVectorRenderer_;
    // Manages lights used to light the sprites.
    LightManager lightManager_;

    // Camera used to view GUI.
    Camera2D guiCamera_;
    // Constructs and manages sprites used in GUI.
    SpritePlainManager guiSpriteManager_;
    // Renderers GUI sprites.
    SpritePlainRenderer guiSpriteRenderer_;
    // Renders GUI vector graphics.
    VectorRenderer guiVectorRenderer_;

    // Loads, manages and renders fonts.
    FontRenderer fontRenderer_;

    // Ensures game updates happen with a fixed time step while drawing can happen at any FPS.
    GameTime gameTime_;
    // FPS counter.
    EventCounter fpsCounter_;
    // Mouse position. Used for camera movement.
    vec2u mousePosition_;
    // Mouse position change since the previous position.
    vec2i mousePositionChange_;


    // Sprite used to draw the "player".
    Sprite* sprite_;

    // Big sprite to show off lighting.
    Sprite* bigSprite_;

    // Sprite used to draw point lights.
    Sprite* pointLightSprite_;

    // Isometric map the demo "plays in".
    Map map_;

    // Z rotation of the "player".
    float playerRotationZ_ = 0.0f;

    // 3D position of the "player".
    vec3 playerPosition_ = vec3(0, 0, 45);

    // Test directional light 1.
    DirectionalLight directional1;

    // Rotation of directional light 1 around the X and Z axis.
    float directional1RotationZ;

    // Test directional light 2.
    DirectionalLight directional2;

    // Test point light 1.
    PointLight point1;
    // Test point light 2.
    PointLight point2;
    // Test point light 3.
    PointLight point3;


public:
    /// Construct Demo with specified data directory.
    ///
    /// Throws:  StartupException on failure.
    this(VFSDir dataDir)
    {
        dataDir_ = dataDir;
        writeln("Initializing Demo...");

        initConfig();
        initPlatform();
        writeln("Initialized Platform");
        scope(failure){destroyPlatform();}
        initRenderer();
        writeln("Initialized Video");
        scope(failure){destroyRenderer();}

        gameTime_ = new GameTime();

        // Initialize camera.
        camera_ = new Camera2D();
        scope(failure){destroy(camera_); camera_ = null;}
        camera_.size = renderer_.viewportSize;
        // Initialize GUI camera.
        guiCamera_ = new Camera2D();
        scope(failure){destroy(guiCamera_); guiCamera_ = null;}
        guiCamera_.size = renderer_.viewportSize;
        guiCamera_.center = vec2i(guiCamera_.size.x / 2, guiCamera_.size.y / 2);

        mousePosition_ = vec2u(renderer_.viewportSize.x / 2, renderer_.viewportSize.y / 2);

        // Update FPS display every second.
        fpsCounter_ = EventCounter(1.0);
        fpsCounter_.update.connect((real fps){platform_.windowCaption = "FPS: " ~ to!string(fps);});


        initSprites();
        scope(failure){destroySprites();}

        // Initialize the demo itself.

        fontRenderer_ = new FontRenderer(renderer_, dataDir_, guiCamera_);
        scope(failure){destroy(fontRenderer_);}
        initGUI();
        scope(failure){destroyGUI();}


        // Initialize the test sprites.
        sprite_ = spriteManager_.loadSprite("sprites/player");
        bigSprite_ = spriteManager_.loadSprite("sprites/test/big");
        pointLightSprite_ = spriteManager_.loadSprite("sprites/lights/point");
        if(sprite_ is null || bigSprite_ is null || pointLightSprite_ is null)
        {
            throw new StartupException("Failed to initialize test sprites.");
        }
        scope(failure)
        {
            free(sprite_);           sprite_ = null;
            free(bigSprite_);        bigSprite_ = null;
            free(pointLightSprite_); pointLightSprite_ = null;
        }

        // Create and register light sources.
        directional1 = DirectionalLight(vec3(1.0, 0.0, 0.8), rgb!"181830");
        directional2 = DirectionalLight(vec3(0.0, -1.0, 0.2), rgb!"FFEFCF");
        point1 = PointLight(vec3(40.0, 200.0, 70.0), rgb!"FF0000", 0.9f);
        point2 = PointLight(vec3(100.0, 400.0, 70.0), rgb!"FFFF00", 0.9f);
        point3 = PointLight(vec3(100.0, 400.0, 70.0), rgb!"EFEFFF", 0.3f);

        map_ = generateTestMap(vec2u(80, 160));
        //map_ = loadMap(dataDir_, "maps/testMap.yaml");

        lightManager_ = spriteRenderer_.lightManager;
        const mapBounds = map_.boundingSquare;
        // Adding extra 1024 units to decrease the number of lights with bounds intersecting
        // the border of the bounding area (with quadtree, that decreases performance due to
        // an array fallback).
        lightManager_.boundingArea = 
            CenteredSquare(mapBounds.center, mapBounds.halfSize + 1024.0f);
        with(lightManager_)
        {
            unlock();
            registerDirectionalLight(&directional1);
            registerDirectionalLight(&directional2);
            registerPointLight(&point1);
            registerPointLight(&point2);
            registerPointLight(&point3);
            ambientLight = vec3(0.003, 0.003, 0.006);
            lock();
        }

        map_.loadTiles(dataDir_, spriteManager_);
        writeln("Map size in bytes: ", map_.memoryBytes);
    }

    /// Deinitialize the demo.
    ~this()
    {
        writeln("Destroying Demo...");
        map_.deleteTiles();
        destroy(map_);
        map_ = null;
        if(sprite_ !is null){free(sprite_);}
        if(bigSprite_ !is null){free(bigSprite_);}
        if(pointLightSprite_ !is null){free(pointLightSprite_);}

        destroyGUI();
        if(fontRenderer_ !is null){destroy(fontRenderer_);}
        if(guiCamera_ !is null){destroy(guiCamera_);}
        if(camera_ !is null){destroy(camera_);}
        destroySprites();
        destroyRenderer();
        destroyPlatform();
    }

    /// Run the main loop of the demo.
    void run()
    {
        ulong iterations = 0;
        scope(failure)
        {
            writeln("Failure in Demo main loop, iteration ", iterations);
        }

        platform_.key.connect(&keyHandler);
        platform_.mouseMotion.connect(&mouseMotionHandler);

        while(platform_.run() && continue_)
        {
            // Game logic has a locked time step. Rendering does not.
            gameTime_.doGameUpdates
            ({
                lightManager_.unlock();
                point3.intensity = point3.intensity * 1.001;
                point3.position = playerPosition_ + vec3(40.0f, 0.0f, 0.0f);
                directional2.direction =
                    vec3(mat4.xrotation(directional1RotationZ * degToRad) *
                         vec4(0.0, -1.0, 0.2, 1.0));
                handleCameraMovement();
                lightManager_.lock();
                return false;
            });

            const playerAABB = AABB(sprite_.boundingBox.min + playerPosition_,
                                    sprite_.boundingBox.max + playerPosition_);
            const point1AABB = AABB(pointLightSprite_.boundingBox.min + point1.position,
                                    pointLightSprite_.boundingBox.max + point1.position);
            const point2AABB = AABB(pointLightSprite_.boundingBox.min + point2.position,
                                    pointLightSprite_.boundingBox.max + point2.position);
            void drawEntitiesInTile
                (Sprite3DRenderer spriteRenderer, ref const AABB aabb, 
                 ref const Map.SpriteDrawParams params)
            {
                // Once we have multiple entities, we'll use a spatial manager 
                // based on cells/layers so we'll just directly draw entities within the cell/layer
                // and avoid doing AABB intersection checks every time.

                // The spriteRenderer clips drawn pixels to the 3D area specified by aabb, so
                // we draw once per each cell the object is in.
                if(aabb.intersects(playerAABB))
                {
                    spriteRenderer.drawSprite(sprite_, playerPosition_, 
                                              vec3(0.0f, 0.0f, playerRotationZ_));
                }

                if(aabb.intersects(point1AABB))
                {
                    spriteRenderer.drawSprite(pointLightSprite_, point1.position, 
                                              vec3(0.0f, 0.0f, 0.0f));
                }

                if(aabb.intersects(point2AABB))
                {
                    spriteRenderer.drawSprite(pointLightSprite_, point2.position, 
                                              vec3(0.0f, 0.0f, 0.0f));
                }
            }

            bool frame(Renderer renderer)
            {
                fpsCounter_.event();
                map_.draw(spriteRenderer_, camera_, &drawEntitiesInTile);
                spriteRenderer_.startDrawing();
                spriteRenderer_.clipBounds = AABB(vec3(-10000, -10000, -10000),
                                                  vec3( 10000,  10000,  10000));
                spriteRenderer_.drawSprite(bigSprite_, vec3(0.0f, 1024.0f, 128.0f),
                                           vec3(0.0f, 0.0f, playerRotationZ_));
                spriteRenderer_.stopDrawing();

                if(guiEnabled_)
                {
                    guiSystem_.render();
                }
                dimetricVectorRenderer_.startDrawing();
                dimetricVectorRenderer_.drawCenteredSquare
                    (CenteredSquare(point3.position.xy, 
                                    point3.boundingSphere.radius),
                     rgb!"E0E0FF");
                dimetricVectorRenderer_.stopDrawing();

                return true;
            }
            renderer_.renderFrame(&frame);
            ++iterations;
        }
    }

private:
    /// Load configuration from YAML.
    void initConfig()
    {
        try
        {
            auto configFile = dataDir_.file("config.yaml");
            config_ = loadYAML(configFile);
        }
        catch(YAMLException e)
        {
            throw new StartupException("Failed to load main config file: " ~ e.msg);
        }
        catch(VFSException e)
        {
            throw new StartupException("Failed to load main config file: " ~ e.msg);
        }
    }

    /// Initialize the Platform subsystem. Throws StartupException on failure.
    void initPlatform()
    {
        try
        {
            platform_ = new SDL2Platform();
        }
        catch(PlatformException e)
        {
            platform_ = null;
            throw new StartupException("Failed to initialize platform: " ~ e.msg);
        }
    }

    /// Init the GUI subsystem.
    ///
    /// Throws: StartupException on failure.
    void initGUI()
    {
        try
        {
            guiSystem_ = new GUISystem(platform_, guiSpriteManager_,
                                       guiSpriteRenderer_, guiVectorRenderer_, 
                                       fontRenderer_, dataDir_);
            guiSystem_.setGUIArea(vec2i(0, 0), vec2i(renderer_.viewportSize));
            auto guiFile = dataDir_.dir("gui").file("mainGUI.yaml");
            auto guiRoot = guiSystem_.loadWidgetTree(loadYAML(guiFile));
            guiSystem_.rootSlot.connect(guiRoot);
        }
        catch(GUIInitException e)
        {
            throw new StartupException("Failed to initialize GUI: " ~ to!string(e));
        }
        catch(YAMLException e)
        {
            throw new StartupException(
                "Failed to initialize GUI due to a YAML error: " ~ to!string(e));
        }
        catch(VFSException e)
        {
            throw new StartupException(
                "Failed to initialize GUI due to a VFS error: " ~ e.msg);
        }
    }

    /// Initialize sprite loading/rendering objects.
    void initSprites()
    {
        spriteManager_ = new Sprite3DManager(renderer_, dataDir_);
        scope(failure){destroy(spriteManager_); spriteManager_ = null;}
        guiSpriteManager_ = new SpritePlainManager(renderer_, dataDir_);
        scope(failure){destroy(guiSpriteManager_); guiSpriteManager_ = null;}

        // Initialize the sprite renderer.
        try
        {
            spriteRenderer_ =
                Sprite3DManager.constructSpriteRenderer(renderer_, dataDir_, camera_);
            spriteRenderer_.verticalAngle = 30.0f;
            guiSpriteRenderer_ =
                SpritePlainManager.constructSpriteRenderer(renderer_, dataDir_, guiCamera_);
            guiVectorRenderer_      = new VectorRenderer(renderer_, dataDir_, guiCamera_);
            dimetricVectorRenderer_ = new VectorRenderer(renderer_, dataDir_, camera_);
            dimetricVectorRenderer_.useDimetric = true;
        }
        catch(SpriteRendererInitException e)
        {
            throw new StartupException("Failed to initialize sprite renderer: " ~ e.msg);
        }

        try
        {
            auto sprites      = config_["sprites"];
            const lowBitDepth = sprites["lowBitDepth"].as!bool;

            if(lowBitDepth){writeln("Using lower sprite bit depth");}
            Sprite3DManager.SpritePage.lowBitDepth    = lowBitDepth;
            SpritePlainManager.SpritePage.lowBitDepth = lowBitDepth;
        }
        catch(YAMLException e)
        {
            // Not an error if these are not specified.
            return;
        }
    }

    /// Initialize the renderer. Throws StartupException on failure.
    void initRenderer()
    {
        try{rendererContainer_ = new RendererContainer();}
        catch(RendererInitException e)
        {
            throw new StartupException("Failed to initialize renderer dependencies: " ~ e.msg);
        }

        auto video       = config_["video"];
        const width      = video["width"].as!uint;
        const height     = video["height"].as!uint;
        const depth      = video["depth"].as!uint;
        const format     = depth == 16 ? ColorFormat.RGB_565 : ColorFormat.RGBA_8;
        const fullscreen = video["fullscreen"].as!bool;

        if(![16, 32].canFind(depth))
        {
            writeln("Unsupported video mode depth: ", depth,
                    " - falling back to 32bit");
        }

        renderer_ = rendererContainer_.produce!SDL2GLRenderer
                    (platform_, width, height, format, fullscreen);

        // Failed to initialize renderer, clean up.
        if(renderer_ is null)
        {
            rendererContainer_.destroy();
            clear(rendererContainer_);
            throw new StartupException("Failed to initialize renderer.");
        }
    }

    /// Reload the renderer. On failure, throws RendererInitException and the renderer is null.
    void reloadRenderer()
    {
        // Destroy the current renderer.
        assert(renderer_ !is null,
               "Trying to reload renderer, but there's no preexisting renderer");
        spriteRenderer_.prepareForRendererSwitch();
        guiVectorRenderer_.prepareForRendererSwitch();
        dimetricVectorRenderer_.prepareForRendererSwitch();
        guiSpriteRenderer_.prepareForRendererSwitch();
        spriteManager_.prepareForRendererSwitch();
        guiSpriteManager_.prepareForRendererSwitch();
        fontRenderer_.prepareForRendererSwitch();
        destroyRenderer();

        // Ugly, but works.
        try
        {
            initRenderer();
        }
        catch(StartupException e)
        {
            throw new RendererInitException(e.msg);
        }

        fontRenderer_.switchRenderer(renderer_);
        guiSpriteManager_.switchRenderer(renderer_);
        spriteManager_.switchRenderer(renderer_);
        guiSpriteRenderer_.switchRenderer(renderer_);
        guiVectorRenderer_.switchRenderer(renderer_);
        dimetricVectorRenderer_.switchRenderer(renderer_);
        spriteRenderer_.switchRenderer(renderer_);
    }

    /// Destroy sprite loading/rendering objects.
    void destroySprites()
    {
        destroy(guiVectorRenderer_);      guiVectorRenderer_ = null;
        destroy(dimetricVectorRenderer_); dimetricVectorRenderer_ = null;
        destroy(guiSpriteRenderer_);      guiSpriteRenderer_ = null;
        destroy(spriteRenderer_);         spriteRenderer_    = null;
        destroy(spriteManager_);          spriteManager_     = null;
        destroy(guiSpriteManager_);       guiSpriteManager_  = null;
    }

    /// Destroy the renderer.
    void destroyRenderer()
    {
        //Renderer might be already destroyed in exceptional circumstances
        //such as a failed renderer reset.
        if(renderer_ is null){return;}
        rendererContainer_.destroy();
        clear(rendererContainer_);
        renderer_ = null;
    }

    /// Destroy the Platform subsystem.
    void destroyPlatform()
    {
        destroy(platform_);
        platform_ = null;
    }

    /// Destroy the GUI subsystem.
    void destroyGUI()
    {
        destroy(guiSystem_);
        guiSystem_ = null;
    }

    /// Exit the demo.
    void exit(){continue_ = false;}

    /// Process keyboard input.
    /// 
    /// Params:  state   = State of the key.
    ///          key     = Keyboard key.
    ///          unicode = Unicode value of the key.
    void keyHandler(KeyState state, Key key, dchar unicode)
    {
        // Rotate a 2D vector by specified angle and return it as a 3D vector (with Z == 0).
        static vec3 rotate(vec2 rhs, float angle) pure @safe nothrow
        {
            const cs = cos(angle);
            const sn = sin(angle);
            return vec3(rhs.x * cs - rhs.y * sn, rhs.x * sn + rhs.y * cs, 0.0);
        }
        const angle = playerRotationZ_;
        lightManager_.unlock();
        scope(exit){lightManager_.lock();}
        if(state == KeyState.Pressed) switch(key) with(Key)
        {
            case Escape: exit(); break;
            // "Player" movement.
            case Left:  playerRotationZ_ += 0.1;             break;
            case Right: playerRotationZ_ -= 0.1;             break;
            case Up, K_w:
                if(platform_.isKeyPressed(LeftCtrl))
                {
                    point1.position += vec3(4.0f, 0.0f, 0.0f);
                }
                else if(platform_.isKeyPressed(LeftShift))
                {
                    point2.position += vec3(4.0f, 0.0f, 0.0f);
                }
                else 
                {
                    playerPosition_ += rotate(vec2(8.0f, 0.0f), angle);
                }
                break;
            case Down, K_s:
                if(platform_.isKeyPressed(LeftCtrl))
                {
                    point1.position -= vec3(4.0f, 0.0f, 0.0f);
                }
                else if(platform_.isKeyPressed(LeftShift))
                {
                    point2.position -= vec3(4.0f, 0.0f, 0.0f);
                }
                else 
                {
                    playerPosition_ -= rotate(vec2(8.0f, 0.0f), angle);
                }
                break;
            case K_a:
                if(platform_.isKeyPressed(LeftCtrl))
                {
                    point1.position += vec3(0.0f, 4.0f, 0.0f);
                }
                else if(platform_.isKeyPressed(LeftShift))
                {
                    point2.position += vec3(0.0f, 4.0f, 0.0f);
                }
                else 
                {
                    playerPosition_ += rotate(vec2(0.0f, 8.0f), angle);
                }
                break;
            case K_d:
                if(platform_.isKeyPressed(LeftCtrl))
                {
                    point1.position -= vec3(0.0f, 4.0f, 0.0f);
                }
                else if(platform_.isKeyPressed(LeftShift))
                {
                    point2.position -= vec3(0.0f, 4.0f, 0.0f);
                }
                else 
                {
                    playerPosition_ -= rotate(vec2(0.0f, 8.0f), angle);
                }
                break;
            case K_q:
                if(platform_.isKeyPressed(LeftCtrl))
                {
                    point1.position += vec3(0.0f, 0.0f, 4.0f);
                }
                else if(platform_.isKeyPressed(LeftShift))
                {
                    point2.position += vec3(0.0f, 0.0f, 4.0f);
                }
                else 
                {
                    playerPosition_ += vec3(0.0f, 0.0f, 8.0f);
                }
                break;
            case K_e:
                if(platform_.isKeyPressed(LeftCtrl))
                {
                    point1.position -= vec3(0.0f, 0.0f, 4.0f);
                }
                else if(platform_.isKeyPressed(LeftShift))
                {
                    point2.position -= vec3(0.0f, 0.0f, 4.0f);
                }
                else 
                {
                    playerPosition_ -= vec3(0.0f, 0.0f, 8.0f);
                }
                break;
            case K_g:
                guiEnabled_ = !guiEnabled_;
                break;
            case K_r:
                // Used to test renderer switching.
                reloadRenderer();
                break;

                // Light on-off switches
            case K_1:
                if(lightManager_.isDirectionalLightRegistered(&directional1))
                {
                    lightManager_.unregisterDirectionalLight(&directional1);
                }
                else 
                {
                    lightManager_.registerDirectionalLight(&directional1);
                }
                break;
            case K_2:
                if(lightManager_.isDirectionalLightRegistered(&directional2))
                {
                    lightManager_.unregisterDirectionalLight(&directional2);
                }
                else 
                {
                    lightManager_.registerDirectionalLight(&directional2);
                }
                break;
            case K_3:
                if(lightManager_.isPointLightRegistered(&point1))
                {
                    lightManager_.unregisterPointLight(&point1);
                }
                else 
                {
                    lightManager_.registerPointLight(&point1);
                }
                break;
            case K_4:
                if(lightManager_.isPointLightRegistered(&point2))
                {
                    lightManager_.unregisterPointLight(&point2);
                }
                else 
                {
                    lightManager_.registerPointLight(&point2);
                }
                break;
            case K_5:
                if(lightManager_.isPointLightRegistered(&point3))
                {
                    lightManager_.unregisterPointLight(&point3);
                }
                else 
                {
                    lightManager_.registerPointLight(&point3);
                }
                break;
            // Camera zoom.
            case Plus, NP_Plus:   camera_.zoom = camera_.zoom * 1.25; break;
            case Minus, NP_Minus: camera_.zoom = camera_.zoom * 0.8;  break;
            default: break;
        }
    }

    /// Process mouse motion.
    ///
    /// Params:  position = Mouse position (in pixels).
    ///          change   = Position change since the last mouseMotionHandler() call.
    void mouseMotionHandler(vec2u position, vec2i change)
    {
        mousePosition_ = position;
        if(platform_.isKeyPressed(Key.LeftCtrl))
        {
            mousePositionChange_ = change;
        }
    }

    /// Move the camera if mouse is on a window edge.
    void handleCameraMovement() @trusted
    {
        const bounds = renderer_.viewportSize;
        const borderWidth = 48;
        // 600 pixels per second.
        const cameraMovement = cast(int)(600 * gameTime_.timeStep);
        vec2i offset = vec2i(0, 0);
        if(mousePosition_.x < borderWidth)           {offset.x = -cameraMovement;}
        if(mousePosition_.x > bounds.x - borderWidth){offset.x = cameraMovement;}
        if(mousePosition_.y < borderWidth)           {offset.y = cameraMovement;}
        if(mousePosition_.y > bounds.y - borderWidth){offset.y = -cameraMovement;}
        camera_.center = camera_.center + offset;
        if(platform_.isKeyPressed(Key.LeftCtrl))
        {
            directional1RotationZ += mousePositionChange_.y * gameTime_.timeStep * 30;
            directional1RotationZ = clamp(directional1RotationZ, -90.0f, 90.0f);
        }
    }
}
