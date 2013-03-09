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

import dgamevfs._;
import gl3n.aabb;
import gl3n.linalg;

import color;
import demo.camera2d;
import demo.light;
import demo.map;
import demo.sprite;
import memory.memory;
import platform.platform;
import time.eventcounter;
import time.gametime;
import platform.sdl2platform;
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
    // Main config file (YAML).
    YAMLNode config_;
    // Continue running?
    bool continue_ = true;

    // Camera used to view the scene.
    Camera2D camera_;
    // Handles rendering sprites with lighting.
    SpriteRenderer spriteRenderer_;

    // Ensures game updates happen with a fixed time step while drawing can happen at any FPS.
    GameTime gameTime_;
    // FPS counter.
    EventCounter fpsCounter_;
    // Mouse position. Used for camera movement.
    vec2u mousePosition_;



    // Demo data follows.

    // Sprite used to draw the "player".
    Sprite* sprite_;

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
    // Test directional light 2.
    DirectionalLight directional2;

    // Test point light 1.
    PointLight point1;
    // Test point light 2.
    PointLight point2;

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

        // Update FPS display every second.
        fpsCounter_ = EventCounter(1.0);
        fpsCounter_.update.connect((real fps){platform_.windowCaption = "FPS: " ~ to!string(fps);});


        // Initialize the demo itself.

        // Initialize the sprite renderer.
        try
        {
            spriteRenderer_ = new SpriteRenderer(renderer_, dataDir_, 30.0f, camera_);
        }
        catch(SpriteRendererInitException e)
        {
            throw new StartupException("Failed to initialize sprite renderer: " ~ e.msg);
        }
        scope(failure){destroy(spriteRenderer_); spriteRenderer_ = null;}

        // Initialize the test sprite.
        sprite_ = loadSprite(renderer_, dataDir_, "sprites/player");
        pointLightSprite_ = loadSprite(renderer_, dataDir_, "sprites/lights/point");
        if(sprite_ is null) {throw new StartupException("Failed to initialize test sprite.");}
        scope(failure){free(sprite_); sprite_ = null;}

        // Create and register light sources.
        directional1 = DirectionalLight(vec3(1.0, 0.0, 0.8), rgb!"C0C0F0");
        directional2 = DirectionalLight(vec3(1.0, 1.0, 0.0), rgb!"202020");
        point1 = PointLight(vec3(40.0, 200.0, 70.0), rgb!"FF0000", 1.1f);
        point2 = PointLight(vec3(100.0, 400.0, 70.0), rgb!"FFFF00", 1.1f);
        spriteRenderer_.registerDirectionalLight(&directional1);
        spriteRenderer_.registerDirectionalLight(&directional2);
        spriteRenderer_.registerPointLight(&point1);
        spriteRenderer_.registerPointLight(&point2);
        spriteRenderer_.ambientLight = vec3(0.1, 0.1, 0.1);

        map_ = generateTestMap();
        /*map_ = loadMap(dataDir_, "maps/testMap.yaml");*/
        map_.loadTiles(dataDir_, renderer_);
        writeln("Map size in bytes: ", map_.memoryBytes);
    }

    /// Deinitialize the demo.
    ~this()
    {
        writeln("Destroying Demo...");
        map_.deleteTiles();
        destroy(map_);
        if(sprite_ !is null){free(sprite_);}
        if(pointLightSprite_ !is null){free(pointLightSprite_);}
        if(spriteRenderer_ !is null){destroy(spriteRenderer_);}
        if(camera_ !is null){destroy(camera_);}
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
                handleCameraMovement();
                return false;
            });

            void drawEntitiesInTile
                (SpriteRenderer spriteRenderer, ref const AABB aabb, ref const Map.SpriteDrawParams params)
            {
                // Once we have multiple entities, we'll use a spatial manager 
                // based on cells/layers so we'll just directly draw entities within the cell/layer
                // and avoid doing AABB intersection checks every time.

                // The spriteRenderer clips drawn pixels to the 3D area specified by aabb, so
                // we draw once per each cell the object is in.
                if(aabb.intersects(AABB(sprite_.boundingBox.min + playerPosition_,
                                        sprite_.boundingBox.max + playerPosition_)))
                {
                    spriteRenderer.drawSprite(sprite_, playerPosition_, 
                                              vec3(0.0f, 0.0f, playerRotationZ_));
                }

                foreach(light; [&point1, &point2])
                {
                    if(aabb.intersects(AABB(sprite_.boundingBox.min + light.position,
                                            sprite_.boundingBox.max + light.position)))
                    {
                        spriteRenderer.drawSprite(pointLightSprite_, light.position, 
                                                   vec3(0.0f, 0.0f, 0.0f));
                    }
                }
            }

            bool frame(Renderer renderer)
            {
                fpsCounter_.event();
                map_.draw(spriteRenderer_, camera_, &drawEntitiesInTile);
                /*
                spriteRenderer_.startDrawing();
                spriteRenderer_.drawSprite(sprite_, vec3(playerPosition_), 
                                        vec3(0.0f, 0.0f, playerRotationZ_));
                spriteRenderer_.stopDrawing();
                */
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

    /// Initialize the renderer. Throws StartupException on failure.
    void initRenderer()
    {
        try{rendererContainer_ = new RendererContainer();}
        catch(RendererInitException e)
        {
            throw new StartupException("Failed to initialize renderer dependencies: " ~ e.msg);
        }

        // Load config options (not sure if anyone will use this...).
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
        clear(platform_);
        platform_ = null;
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
        if(state == KeyState.Pressed) switch(key) with(Key)
        {
            case Escape: exit(); break;
            // "Player" movement.
            case Left:  playerRotationZ_ += 0.1;             break;
            case Right: playerRotationZ_ -= 0.1;             break;
            case Up, K_w:   playerPosition_ += rotate(vec2(8.0f, 0.0f), angle); break;
            case Down, K_s: playerPosition_ -= rotate(vec2(8.0f, 0.0f), angle); break;
            case K_a:       playerPosition_ += rotate(vec2(0.0f, 8.0f), angle); break;
            case K_d:       playerPosition_ -= rotate(vec2(0.0f, 8.0f), angle); break;
            case K_q:       playerPosition_ += vec3(0.0f, 0.0f, 8.0f); break;
            case K_e:       playerPosition_ -= vec3(0.0f, 0.0f, 8.0f); break;

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
    }

    /// Move the camera if mouse is on a window edge.
    void handleCameraMovement() @safe pure nothrow
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
    }
}
