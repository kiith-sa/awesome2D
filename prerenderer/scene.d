//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Graphics scene of the demo.
module prerenderer.scene;


import core.stdc.string;

import std.algorithm;
import std.array;
import std.math;
import std.stdio;
import std.string;
import std.typecons;

import derelict.assimp.assimp;
import derelict.util.exception;
import dgamevfs._;
import gl3n.linalg;

import prerenderer.prerenderer;
import prerenderer.dimetriccamera;
import prerenderer.renderlayer;
import color;
import formats.image;
import image;
import memory.memory;
import util.yaml;
import video.framebuffer;
import video.glslshader;
import video.renderer;
import video.texture;
import video.vertexbuffer;


/// Exception thrown when a scene fails to initialize.
class SceneInitException : Exception 
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Prerenderer scene. Handles camera and model setup.
class Scene
{
private:
    // A simple vertex with a 3D position, texture coordinate and a normal.
    //
    // Currently, all loaded models have to have these vertex attributes.
    // In future, any vertex format should be supported.
    struct Vertex
    {
        // Position of the vertex.
        vec3 position;
        // Texture coordinate of the vertex.
        vec2 texCoord;
        // Surface normal at the vertex.
        vec3 normal;

        // Metadata for Renderer.
        mixin VertexAttributes!(vec3, AttributeInterpretation.Position,
                                vec2, AttributeInterpretation.TexCoord,
                                vec3, AttributeInterpretation.Normal);
    }

    // Has the scene been successfully initialized?
    //
    // Allows graceful failures.
    bool sceneInitialized_;

    // Vertex buffer storing the rendered model as triangles.
    VertexBuffer!Vertex* model_;
    // Maximum distance of any vertex in the model from origin. Used for offset rendering.
    float maxDistanceFromOrigin_;
    // Texture used with the model. If none is specified by user, a placeholder is generated.
    Texture* texture_;
    // Directory to load the texture and model from.
    VFSDir loadDir_;

    // Renderer used to create graphics data structures and for rendering.
    Renderer renderer_;
    // Camera used to view the scene.
    DimetricCamera camera_;
    // Initialized render layers (e.g. diffuse, normal), indexed by their names.
    RenderLayer[string] renderLayers_;

public:
    /// Construct a Scene.
    ///
    /// Params:  loadDir         = Directory to load the model and texture from.
    ///          renderer        = 
    ///          modelFileName   = Filename of the model to use. The model format must
    ///                            be supported by Assimp (lots of formats).
    ///          textureFileName = Filename of the texture to use with the model.
    ///                            If null, a placeholder texture will be generated.
    ///
    /// Throws:  SceneInitException on failure.
    this(VFSDir loadDir, Renderer renderer,
         const string modelFileName, const string textureFileName)
    {
        loadDir_ = loadDir;
        renderer_ = renderer;

        // Load the Assimp library.
        try
        {
            DerelictASSIMP.load();
        }
        catch(DerelictException e)
        {
            throw new SceneInitException
                ("Failed to load DerelictASSIMP library" ~ e.msg);
        }

        // Load the model and texture.
        auto modelAndTransform = loadModel!Vertex(modelFileName);
        loadTexture(textureFileName);
        // (Loaded transform is not yet used.)
        model_ = modelAndTransform[0];
        maxDistanceFromOrigin_ = modelAndTransform[1];

        camera_ = new DimetricCamera();

        sceneInitialized_ = true;
    }

    /// Get metadata about the graphics rendered in the scene as YAML.
    @property void sceneMeta(ref string[] keys, ref YAMLNode[] values) @safe
    in
    {
        assert(keys.length == values.length, 
               "Lengths of arrays specifying a YAML mapping don't match'");
    }
    out
    {
        assert(keys.length == values.length, 
               "Lengths of arrays specifying a YAML mapping don't match'");
    }
    body
    {
        const ext = maxDistanceFromOrigin_;
        YAMLNode extents = 
            YAMLNode(["xMin", "xMax", "yMin", "yMax", "zMin", "zMax"],
                     [-ext,   ext,    -ext,   ext,    -ext,   ext]);
        keys   ~= "posExtents";
        values ~= extents;
    }

    /// Draw the scene with specified rendering parameters.
    void draw(ref const RenderParams params)
    {
        if(!sceneInitialized_) {return;}

        // Select the render layer, lazily initializing.
        auto renderLayer = params.layer in renderLayers_;
        if(renderLayer is null) switch(params.layer)
        {
            case "diffuse":
                renderLayers_[params.layer] = 
                    new DiffuseColorRenderLayer(renderer_.createGLSLShader());
                renderLayer = params.layer in renderLayers_;
                assert(renderLayer !is null, "Diffuse render layer is null after creation");
                break;
            case "normal":
                renderLayers_[params.layer] = 
                    new NormalRenderLayer(renderer_.createGLSLShader());
                renderLayer = params.layer in renderLayers_;
                assert(renderLayer !is null, "Normal render layer is null after creation");
                break;
            case "offset":
                renderLayers_[params.layer] = 
                    new OffsetRenderLayer(renderer_.createGLSLShader());
                renderLayer = params.layer in renderLayers_;
                assert(renderLayer !is null, "Offset render layer is null after creation");
                break;
            default:
                assert(false, "Unknown render layer: " ~ params.layer);
        }

        // Set up the camera.
        const zoom = params.zoom;
        const cameraSize = vec2(1.0f / zoom, 1.0f / zoom * (cast(float)params.height / params.width));
        camera_.setProjection(- 0.5 * cameraSize, cameraSize, 100);
        camera_.verticalAngleRadians = params.verticalAngle / 180.0 * PI;

        const view = camera_.view;

        // Model transform.
        const model        = mat4.zrotation(params.rotation / 180.0 * PI);

        // Calculate the normal matrix from the modelview matrix.
        const normalMatrix = mat3(view * model).inverse().transposed();

        // Bind the texture to texture unit 0.
        texture_.bind(0);
        const projection   = camera_.projection;

        // Pass the matrices to the shader.
        renderLayer.projectionMatrix    = projection;
        renderLayer.normalMatrix        = normalMatrix;
        renderLayer.modelMatrix         = model;
        renderLayer.viewMatrix          = view;
        renderLayer.maxExtentFromOrigin = maxDistanceFromOrigin_;

        // Rendering itself.
        renderLayer.startRender();
        renderer_.drawVertexBuffer(model_, null, renderLayer.shaderProgram);
        renderLayer.endRender();
    }

    /// Destroy the scene.
    ~this()
    {
        if(sceneInitialized_)
        {
            free(model_);
            free(texture_);
            foreach(string name, RenderLayer layer; renderLayers_)
            {
                destroy(layer);
            }
        }
        DerelictASSIMP.unload();
    }

private:
    // Load the rendered model.
    //
    // Params:  filename = Name of the model file. File format must be
    //                     supported by Assimp.
    // 
    // Throws:  SceneInitException on failure.
    //
    // Returns:  A tuple of a vertex buffer containing the model, maximum distance 
    //           of any vertex in the model from origin, and the model's transform matrix.
    Tuple!(VertexBuffer!V*, float, mat4) loadModel(V)(const string filename)
    {
        // Load the scene found in the file.
        //
        // A scene might contain multiple models/meshes, 
        // but only the first will be loaded at this point.
        const aiScene* scene = aiImportFile
            (filename.toStringz,
             aiPostProcessSteps.CalcTangentSpace |      // For normal mapping (future)
             aiPostProcessSteps.Triangulate |           // We can only draw triangles
             aiPostProcessSteps.GenUVCoords |           // Generate UV if mapping is non-UV (e.g. spherical)
             aiPostProcessSteps.TransformUVCoords |     // Don't want do transform UVs in shader
             aiPostProcessSteps.SortByPType);           // Should put free lines/points to the end

        // Failed to load.
        if(scene is null)
        {
            const error = aiGetErrorString();
            const msg = "Error loading model: " ~ cast(string)error[0 .. error.strlen()];
            throw new SceneInitException(msg);
        }

        auto model = renderer_.createVertexBuffer!V(PrimitiveType.Triangles);
        scope(failure) {free(model);}

        // We currently only support single-model scenes.
        // This is used to check for multi-model scenes (which is an error).
        bool haveModel;
        mat4 modelTransform;

        // Convert an Assimp matrix to a gl3n matrix.
        mat4 matrix4AssimpToGl3n(ref const aiMatrix4x4 m) @safe pure nothrow
        {
            with(m)
            {
                return mat4(a1, a2, a3, a4,
                            b1, b2, b3, b4,
                            c1, c2, c3, c4,
                            d1, d2, d3, d4);
            }
        }

        float maxDistanceFromOrigin = 0.0f;

        // Process the scene's nodes recursively.
        //
        // Will load the first model encountered and throw if any other model is found.
        //
        // Throws:  SceneInitException if a model has unsupported vertex format or if
        //          there is more than 1 model.
        void recursiveProcess(const aiScene* scene, const aiNode* node)
        {
            aiMatrix4x4 transformAi = node.mTransformation;
            aiTransposeMatrix4(&transformAi);
            modelTransform = matrix4AssimpToGl3n(transformAi);

            foreach(m; 0 .. node.mNumMeshes)
            {
                const aiMesh* mesh = scene.mMeshes[node.mMeshes[m]];

                // future:
                // applyMaterials(scene.mMaterials[mesh.mMaterialIndex]);

                if(mesh.mNormals is null) 
                {
                    throw new SceneInitException("Meshes without normals are not supported");
                }
                // The first texture coordinates attribute (assimp supports multiple texcoords)
                if(mesh.mTextureCoords[0] is null)
                {
                    assert(false, "TODO implement meshes without texture coordinates");
                }

                // Process the triangles of the mesh (we triangulated at loading).
                for (uint f = 0; f < mesh.mNumFaces; ++f) 
                {
                    const aiFace* face = &mesh.mFaces[f];

                    switch(face.mNumIndices) 
                    {
                        case 1, 2: writeln("Point or line in a mesh. Ignoring."); break;
                        case 3:    break; // OK, triangle
                        // Shouldn't happen anyway due to triangulation at loading.
                        default:
                            throw new SceneInitException("Faces with >3 vertices are not supported");
                    }

                    // We don't use indices at the moment; just create a vertex for each index.
                    foreach(i; 0 .. face.mNumIndices)
                    {
                        int index = face.mIndices[i];
                        auto p = mesh.mVertices[index];
                        auto t = mesh.mTextureCoords[0][index];
                        auto n = mesh.mNormals[index];
                        const pos = vec3(p.x, p.y, p.z);
                        maxDistanceFromOrigin = max(maxDistanceFromOrigin, pos.length);
                        auto v = V(pos, vec2(t.x, t.y), vec3(n.x, n.y, n.z));
                        model.addVertex(v);
                    }
                }
                haveModel = true;
            }

            // Recursively process subnodes.
            foreach(n; 0 .. node.mNumChildren)
            {
                if(haveModel)
                {
                    throw new SceneInitException(
                        "Scenes with more than 1 model node not yet supported");
                }
                recursiveProcess(scene, node.mChildren[n]);
            }
        }

        recursiveProcess(scene, scene.mRootNode);

        // Done loading the model.
        model.lock();
        aiReleaseImport(scene);
        return tuple(model, maxDistanceFromOrigin, modelTransform);
    }

    // Load the texture to use with the model.
    //
    // Params:  textureFileName = File name of the texture.
    //                            If null, a placeholder texture will be generated.
    //
    // Throws:  SceneInitException if the texture could not be loaded.
    void loadTexture(const string textureFileName)
    {
        // Generate placeholder if no texture specified.
        if(textureFileName is null)
        {
            auto image = Image(1024, 1024, ColorFormat.RGBA_8);
            image.generateCheckers(32);
            texture_ = renderer_.createTexture(image);
            return;
        }

        alias SceneInitException E;
        try
        {
            // Load the texture.
            auto textureFile = loadDir_.file(textureFileName);
            if(!textureFile.exists)
            {
                throw new E("Texture file " ~ textureFileName ~ " does not exist");
            }
            Image image;
            readImage(image, textureFile);
            texture_ = renderer_.createTexture(image);
        }
        catch(VFSException e)
        {
            throw new E("Could not load texture " ~ textureFileName ~ ": " ~ e.msg);
        }
        catch(ImageFileException e)
        {
            throw new E("Could not load texture " ~ textureFileName ~ ": " ~ e.msg);
        }
    }
}
