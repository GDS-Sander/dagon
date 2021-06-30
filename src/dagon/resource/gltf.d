/*
Copyright (c) 2021 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003
Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/
module dagon.resource.gltf;

import std.stdio;
import std.path;
import dlib.core.memory;
import dlib.core.ownership;
import dlib.core.stream;
import dlib.filesystem.filesystem;
import dlib.container.array;
import dlib.serialization.json;
import dlib.text.str;
import dlib.math.vector;

import dagon.core.bindings;
import dagon.resource.asset;
import dagon.resource.texture;
import dagon.graphics.drawable;
import dagon.graphics.mesh;
import dagon.graphics.texture;
import dagon.graphics.material;

class GLTFBuffer: Owner
{
    ubyte[] array;
    
    this(InputStream istrm, Owner o)
    {
        super(o);
        
        if (istrm is null)
            return;
        
        array = New!(ubyte[])(istrm.size);
        if (!istrm.fillArray(array))
        {
            writeln("Warning: failed to read buffer");
            Delete(array);
        }
    }
    
    ~this()
    {
        if (array.length)
            Delete(array);
    }
}

class GLTFBufferView: Owner
{
    GLTFBuffer buffer;
    uint offset;
    uint len;
    ubyte[] slice;
    GLenum target;
    
    this(GLTFBuffer buffer, uint offset, uint len, GLenum target, Owner o)
    {
        super(o);
        
        if (buffer is null)
            return;
        
        this.buffer = buffer;
        this.offset = offset;
        this.len = len;
        this.target = target;
        
        if (offset < buffer.array.length && offset+len <= buffer.array.length)
        {
            this.slice = buffer.array[offset..offset+len];
        }
        else
        {
            writeln("Warning: invalid buffer view bounds");
        }
    }
    
    ~this()
    {
    }
}

enum GLTFDataType
{
    Undefined,
    Scalar,
    Vec2,
    Vec3,
    Vec4,
    Mat2,
    Mat3,
    Mat4
}

class GLTFAccessor: Owner
{
    GLTFBufferView bufferView;
    GLTFDataType dataType;
    GLenum componentType;
    uint count;
    
    this(GLTFBufferView bufferView, GLTFDataType dataType, GLenum componentType, uint count, Owner o)
    {
        super(o);
        
        if (bufferView is null)
            return;
        
        this.bufferView = bufferView;
        this.dataType = dataType;
        this.componentType = componentType;
        this.count = count;
    }
    
    ~this()
    {
    }
}

class GLTFMesh: Owner, Drawable
{
    GLTFAccessor positionAccessor;
    GLTFAccessor normalAccessor;
    GLTFAccessor texCoord0Accessor;
    GLTFAccessor indexAccessor;
    Material material;
    
    GLuint vao = 0;
    GLuint vbo = 0;
    GLuint nbo = 0;
    GLuint tbo = 0;
    GLuint eao = 0;
    
    bool canRender = false;
    
    this(GLTFAccessor positionAccessor, GLTFAccessor normalAccessor, GLTFAccessor texCoord0Accessor, GLTFAccessor indexAccessor, Material material, Owner o)
    {
        super(o);
        this.positionAccessor = positionAccessor;
        this.normalAccessor = normalAccessor;
        this.texCoord0Accessor = texCoord0Accessor;
        this.indexAccessor = indexAccessor;
        this.material = material;
    }
    
    void prepareVAO()
    {
        if (positionAccessor is null || 
            normalAccessor is null || 
            texCoord0Accessor is null || 
            indexAccessor is null)
            return;
        
        if (positionAccessor.bufferView.slice.length == 0)
            return;
        if (normalAccessor.bufferView.slice.length == 0)
            return;
        if (texCoord0Accessor.bufferView.slice.length == 0)
            return;
        if (indexAccessor.bufferView.slice.length == 0)
            return;
        
        glGenBuffers(1, &vbo);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, positionAccessor.bufferView.slice.length, positionAccessor.bufferView.slice.ptr, GL_STATIC_DRAW); 
        
        glGenBuffers(1, &nbo);
        glBindBuffer(GL_ARRAY_BUFFER, nbo);
        glBufferData(GL_ARRAY_BUFFER, normalAccessor.bufferView.slice.length, normalAccessor.bufferView.slice.ptr, GL_STATIC_DRAW);
        
        glGenBuffers(1, &tbo);
        glBindBuffer(GL_ARRAY_BUFFER, tbo);
        glBufferData(GL_ARRAY_BUFFER, texCoord0Accessor.bufferView.slice.length, texCoord0Accessor.bufferView.slice.ptr, GL_STATIC_DRAW);
        
        glGenBuffers(1, &eao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, indexAccessor.bufferView.slice.length, indexAccessor.bufferView.slice.ptr, GL_STATIC_DRAW);
        
        glGenVertexArrays(1, &vao);
        glBindVertexArray(vao);
        
        glEnableVertexAttribArray(VertexAttrib.Vertices);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glVertexAttribPointer(VertexAttrib.Vertices, 3, GL_FLOAT, GL_FALSE, 0, null);
        
        glEnableVertexAttribArray(VertexAttrib.Normals);
        glBindBuffer(GL_ARRAY_BUFFER, nbo);
        glVertexAttribPointer(VertexAttrib.Normals, 3, GL_FLOAT, GL_FALSE, 0, null);
        
        glEnableVertexAttribArray(VertexAttrib.Texcoords);
        glBindBuffer(GL_ARRAY_BUFFER, tbo);
        glVertexAttribPointer(VertexAttrib.Texcoords, 2, GL_FLOAT, GL_FALSE, 0, null);
        
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
        
        glBindVertexArray(0);
        
        canRender = true;
    }
    
    void render(GraphicsState* state)
    {
        if (canRender)
        {
            glBindVertexArray(vao);
            glDrawElements(GL_TRIANGLES, indexAccessor.count, indexAccessor.componentType, cast(void*)0);
            glBindVertexArray(0);
        }
    }
    
    ~this()
    {
        if (canRender)
        {
            glDeleteVertexArrays(1, &vao);
            glDeleteBuffers(1, &vbo);
            glDeleteBuffers(1, &nbo);
            glDeleteBuffers(1, &tbo);
            glDeleteBuffers(1, &eao);
        }
    }
}

class GLTFAsset: Asset
{
    AssetManager assetManager;
    String str;
    JSONDocument doc;
    Array!GLTFBuffer buffers;
    Array!GLTFBufferView bufferViews;
    Array!GLTFAccessor accessors;
    Array!GLTFMesh meshes;
    Array!TextureAsset images;
    Array!Texture textures;
    Array!Material materials;
    
    this(Owner o)
    {
        super(o);
    }
    
    ~this()
    {
        release();
    }
    
    override bool loadThreadSafePart(string filename, InputStream istrm, ReadOnlyFileSystem fs, AssetManager mngr)
    {
        assetManager = mngr;
        string rootDir = dirName(filename);
        str = String(istrm);
        doc = New!JSONDocument(str.toString);
        loadBuffers(doc.root, fs, rootDir);
        loadBufferViews(doc.root);
        loadAccessors(doc.root);
        loadImages(doc.root, fs, rootDir);
        loadTextures(doc.root);
        loadMaterials(doc.root);
        loadMeshes(doc.root);
        return true;
    }
    
    void loadBuffers(JSONValue root, ReadOnlyFileSystem fs, string rootDir)
    {
        if ("buffers" in root.asObject)
        {
            foreach(buffer; root.asObject["buffers"].asArray)
            {
                auto buf = buffer.asObject;
                if ("uri" in buf)
                {
                    String bufFilename = String(rootDir);
                    bufFilename ~= "/";
                    bufFilename ~= buf["uri"].asString;
                    
                    FileStat fstat;
                    if (fs.stat(bufFilename.toString, fstat))
                    {
                        auto bufStream = fs.openForInput(bufFilename.toString);
                        GLTFBuffer b = New!GLTFBuffer(bufStream, this);
                        buffers.insertBack(b);
                        Delete(bufStream);
                    }
                    else
                    {
                        writeln("Warning: buffer file \"", bufFilename, "\" not found");
                        GLTFBuffer b = New!GLTFBuffer(null, this);
                        buffers.insertBack(b);
                    }
                    
                    bufFilename.free();
                }
            }
        }
    }
    
    void loadBufferViews(JSONValue root)
    {
        if ("bufferViews" in root.asObject)
        {
            foreach(bufferView; root.asObject["bufferViews"].asArray)
            {
                auto bv = bufferView.asObject;
                uint bufferIndex = 0;
                uint byteOffset = 0;
                uint byteLength = 0;
                GLenum target = GL_ARRAY_BUFFER;
                
                if ("buffer" in bv)
                    bufferIndex = cast(uint)bv["buffer"].asNumber;
                if ("byteOffset" in bv)
                    byteOffset = cast(uint)bv["byteOffset"].asNumber;
                if ("byteLength" in bv)
                    byteLength = cast(uint)bv["byteLength"].asNumber;
                if ("target" in bv)
                    target = cast(GLenum)bv["target"].asNumber;
                
                if (bufferIndex < buffers.length)
                {
                    GLTFBufferView bufv = New!GLTFBufferView(buffers[bufferIndex], byteOffset, byteLength, target, this);
                    bufferViews.insertBack(bufv);
                }
                else
                {
                    writeln("Warning: can't create buffer view for nonexistent buffer ", bufferIndex);
                    GLTFBufferView bufv = New!GLTFBufferView(null, 0, 0, 0, this);
                    bufferViews.insertBack(bufv);
                }
            }
        }
    }
    
    void loadAccessors(JSONValue root)
    {
        if ("accessors" in root.asObject)
        {
            foreach(i, accessor; root.asObject["accessors"].asArray)
            {
                auto acc = accessor.asObject;
                uint bufferViewIndex = 0;
                GLenum componentType;
                string type;
                uint count = 0;
                
                if ("bufferView" in acc)
                    bufferViewIndex = cast(uint)acc["bufferView"].asNumber;
                if ("componentType" in acc)
                    componentType = cast(GLenum)acc["componentType"].asNumber;
                if ("type" in acc)
                    type = acc["type"].asString;
                if ("count" in acc)
                    count = cast(uint)acc["count"].asNumber;
                
                GLTFDataType dataType = GLTFDataType.Undefined;
                if (type == "SCALAR")
                    dataType = GLTFDataType.Scalar;
                else if (type == "VEC2")
                    dataType = GLTFDataType.Vec2;
                else if (type == "VEC3")
                    dataType = GLTFDataType.Vec3;
                else if (type == "VEC4")
                    dataType = GLTFDataType.Vec4;
                else if (type == "MAT2")
                    dataType = GLTFDataType.Mat2;
                else if (type == "MAT3")
                    dataType = GLTFDataType.Mat3;
                else if (type == "MAT4")
                    dataType = GLTFDataType.Mat4;
                else
                    writeln("Warning: unsupported data type for accessor ", i);
                
                if (bufferViewIndex < bufferViews.length)
                {
                    GLTFAccessor ac = New!GLTFAccessor(bufferViews[bufferViewIndex], dataType, componentType, count, this);
                    accessors.insertBack(ac);
                }
                else
                {
                    writeln("Warning: can't create accessor for nonexistent buffer view ", bufferViewIndex);
                    GLTFAccessor ac = New!GLTFAccessor(null, dataType, componentType, count, this);
                    accessors.insertBack(ac);
                }
            }
        }
    }
    
    void loadImages(JSONValue root, ReadOnlyFileSystem fs, string rootDir)
    {
        if ("images" in root.asObject)
        {
            foreach(i, img; root.asObject["images"].asArray)
            {
                auto im = img.asObject;
                
                if ("uri" in im)
                {
                    String imgFilename = String(rootDir);
                    imgFilename ~= "/";
                    imgFilename ~= im["uri"].asString;
                    
                    auto ta = New!TextureAsset(assetManager.imageFactory, assetManager.hdrImageFactory, this);
                    
                    FileStat fstat;
                    if (fs.stat(imgFilename.toString, fstat))
                    {
                        bool res = assetManager.loadAssetThreadSafePart(ta, imgFilename.toString);
                        if (!res)
                            writeln("Warning: failed to load \"", imgFilename, "\" not found");
                    }
                    else
                    {
                        writeln("Warning: image file \"", imgFilename, "\" not found");
                    }
                    
                    images.insertBack(ta);
                    
                    imgFilename.free();
                }
            }
        }
    }
    
    void loadTextures(JSONValue root)
    {
        if ("textures" in root.asObject)
        {
            foreach(i, tex; root.asObject["textures"].asArray)
            {
                auto te = tex.asObject;
                
                if ("source" in te)
                {
                    uint imageIndex = cast(uint)te["source"].asNumber;
                    TextureAsset img;
                    if (imageIndex < images.length)
                        img = images[imageIndex];
                    else
                        writeln("Warning: can't create texture for nonexistent image ", imageIndex);
                    
                    if (img !is null)
                    {
                        Texture texture = img.texture;
                        textures.insertBack(texture);
                    }
                    else
                    {
                        Texture texture;
                        textures.insertBack(texture);
                    }
                }
            }
        }
    }
    
    void loadMaterials(JSONValue root)
    {
        if ("materials" in root.asObject)
        {
            foreach(i, mat; root.asObject["materials"].asArray)
            {
                auto ma = mat.asObject;
                
                Material material = New!Material(this);
                
                if ("pbrMetallicRoughness" in ma)
                {
                    auto pbr = ma["pbrMetallicRoughness"].asObject;
                    
                    if (pbr && "baseColorTexture" in pbr)
                    {
                        auto bct = pbr["baseColorTexture"].asObject;
                        if ("index" in bct)
                        {
                            uint baseColorTexIndex = cast(uint)bct["index"].asNumber;
                            if (baseColorTexIndex < textures.length)
                            {
                                Texture baseColorTex = textures[baseColorTexIndex];
                                if (baseColorTex)
                                    material.diffuse = baseColorTex;
                            }
                        }
                    }
                    
                    if (pbr && "metallicRoughnessTexture" in pbr)
                    {
                        uint metallicRoughnessTexIndex = cast(uint)pbr["metallicRoughnessTexture"].asObject["index"].asNumber;
                        if (metallicRoughnessTexIndex < textures.length)
                        {
                            Texture metallicRoughnessTex = textures[metallicRoughnessTexIndex];
                            if (metallicRoughnessTex)
                                material.roughnessMetallic = metallicRoughnessTex;
                        }
                    }
                    
                    if (pbr && "metallicFactor" in pbr)
                    {
                        material.metallic = pbr["metallicFactor"];
                    }
                    
                    if (pbr && "roughnessFactor" in pbr)
                    {
                        material.roughness = pbr["roughnessFactor"];
                    }
                }
                
                if ("normalTexture" in ma)
                {
                    uint normalTexIndex = cast(uint)ma["normalTexture"].asObject["index"].asNumber;
                    if (normalTexIndex < textures.length)
                    {
                        Texture normalTex = textures[normalTexIndex];
                        if (normalTex)
                            material.normal = normalTex;
                    }
                }
                
                if ("emissiveTexture" in ma)
                {
                    uint emissiveTexIndex = cast(uint)ma["emissiveTexture"].asObject["index"].asNumber;
                    if (emissiveTexIndex < textures.length)
                    {
                        Texture emissiveTex = textures[emissiveTexIndex];
                        if (emissiveTex)
                            material.emission = emissiveTex;
                    }
                }
                
                materials.insertBack(material);
            }
        }
    }
    
    void loadMeshes(JSONValue root)
    {
        if ("meshes" in root.asObject)
        {
            foreach(i, mesh; root.asObject["meshes"].asArray)
            {
                auto m = mesh.asObject;
                
                if ("primitives" in m)
                {
                    foreach(prim; m["primitives"].asArray)
                    {
                        auto p = prim.asObject;
                        
                        GLTFAccessor positionAccessor;
                        GLTFAccessor normalAccessor;
                        GLTFAccessor texCoord0Accessor;
                        GLTFAccessor indexAccessor;
                        
                        if ("attributes" in p)
                        {
                            auto attributes = p["attributes"].asObject;
                            
                            if ("POSITION" in attributes)
                            {
                                uint positionsAccessorIndex = cast(uint)attributes["POSITION"].asNumber;
                                if (positionsAccessorIndex < accessors.length)
                                    positionAccessor = accessors[positionsAccessorIndex];
                                else
                                    writeln("Warning: can't create position attributes for nonexistent accessor ", positionsAccessorIndex);
                            }
                            
                            if ("NORMAL" in attributes)
                            {
                                uint normalsAccessorIndex = cast(uint)attributes["NORMAL"].asNumber;
                                if (normalsAccessorIndex < accessors.length)
                                    normalAccessor = accessors[normalsAccessorIndex];
                                else
                                    writeln("Warning: can't create normal attributes for nonexistent accessor ", normalsAccessorIndex);
                            }
                            
                            if ("TEXCOORD_0" in attributes)
                            {
                                uint texCoord0AccessorIndex = cast(uint)attributes["TEXCOORD_0"].asNumber;
                                if (texCoord0AccessorIndex < accessors.length)
                                    texCoord0Accessor = accessors[texCoord0AccessorIndex];
                                else
                                    writeln("Warning: can't create texCoord0 attributes for nonexistent accessor ", texCoord0AccessorIndex);
                            }
                        }
                        
                        if ("indices" in p)
                        {
                            uint indicesAccessorIndex = cast(uint)p["indices"].asNumber;
                            if (indicesAccessorIndex < accessors.length)
                                indexAccessor = accessors[indicesAccessorIndex];
                            else
                                writeln("Warning: can't create indices for nonexistent accessor ", indicesAccessorIndex);
                        }
                        
                        Material material;
                        if ("material" in p)
                        {
                            uint materialIndex = cast(uint)p["material"].asNumber;
                            if (materialIndex < materials.length)
                                material = materials[materialIndex];
                            else
                                writeln("Warning: nonexistent material ", materialIndex);
                        }
                        
                        if (positionAccessor is null)
                        {
                            writeln("Warning: mesh ", i, " lacks vertex position attributes");
                            //continue;
                        }
                        if (normalAccessor is null)
                        {
                            writeln("Warning: mesh ", i, " lacks vertex normal attributes");
                            //continue;
                        }
                        if (texCoord0Accessor is null)
                        {
                            writeln("Warning: mesh ", i, " lacks vertex texCoord0 attributes");
                            //continue;
                        }
                        if (indexAccessor is null)
                        {
                            writeln("Warning: mesh ", i, " lacks indices");
                            //continue;
                        }
                        
                        GLTFMesh me = New!GLTFMesh(positionAccessor, normalAccessor, texCoord0Accessor, indexAccessor, material, this);
                        meshes.insertBack(me);
                    }
                }
            }
        }
    }
    
    override bool loadThreadUnsafePart()
    {
        foreach(me; meshes)
        {
            me.prepareVAO();
        }
        
        foreach(img; images)
        {
            img.loadThreadUnsafePart();
        }
        
        return true;
    }
    
    override void release()
    {
        foreach(b; buffers)
            deleteOwnedObject(b);
        buffers.free();
        
        foreach(bv; bufferViews)
            deleteOwnedObject(bv);
        bufferViews.free();
        
        foreach(ac; accessors)
            deleteOwnedObject(ac);
        accessors.free();
        
        foreach(me; meshes)
            deleteOwnedObject(me);
        meshes.free();
        
        foreach(im; images)
            deleteOwnedObject(im);
        images.free();
        
        textures.free();
        
        materials.free();
        
        Delete(doc);
        str.free();
    }
}
