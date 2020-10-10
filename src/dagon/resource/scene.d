/*
Copyright (c) 2019-2020 Timur Gafarov

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

module dagon.resource.scene;

import std.path;

import dlib.core.memory;
import dlib.core.ownership;
import dlib.math.vector;

import dagon.core.application;
import dagon.core.bindings;
import dagon.core.event;
import dagon.core.time;

import dagon.graphics.entity;
import dagon.graphics.camera;
import dagon.graphics.light;
import dagon.graphics.environment;
import dagon.graphics.shapes;
import dagon.graphics.material;
import dagon.graphics.cubemap;

import dagon.resource.asset;
import dagon.resource.obj;
import dagon.resource.image;
import dagon.resource.texture;
//import dagon.resource.font;
import dagon.resource.text;
import dagon.resource.binary;
import dagon.resource.packageasset;

class Scene: EventListener
{
    Application application;
    AssetManager assetManager;
    EntityManager entityManager;
    EntityGroupSpatial spatial;
    EntityGroupSpatialOpaque spatialOpaqueStatic;
    EntityGroupSpatialOpaque spatialOpaqueDynamic;
    EntityGroupSpatialTransparent spatialTransparent;
    EntityGroupBackground background;
    EntityGroupForeground foreground;
    EntityGroupLights lights;
    EntityGroupSunLights sunLights;
    EntityGroupAreaLights areaLights;
    EntityGroupDecals decals;
    Environment environment;
    ShapeBox decalShape;
    bool isLoading = false;
    bool loaded = false;
    bool canRender = false;

    this(Application application)
    {
        super(application.eventManager, application);
        this.application = application;
        entityManager = New!EntityManager(this);
        spatial = New!EntityGroupSpatial(entityManager, this);
        spatialOpaqueStatic = New!EntityGroupSpatialOpaque(entityManager, false, this);
        spatialOpaqueDynamic = New!EntityGroupSpatialOpaque(entityManager, true, this);
        spatialTransparent = New!EntityGroupSpatialTransparent(entityManager, this);
        background = New!EntityGroupBackground(entityManager, this);
        foreground = New!EntityGroupForeground(entityManager, this);
        lights = New!EntityGroupLights(entityManager, this);
        sunLights = New!EntityGroupSunLights(entityManager, this);
        areaLights = New!EntityGroupAreaLights(entityManager, this);
        decals = New!EntityGroupDecals(entityManager, this);

        environment = New!Environment(this);
        decalShape = New!ShapeBox(Vector3f(1, 1, 1), this);

        assetManager = New!AssetManager(eventManager, this);
        beforeLoad();
        isLoading = true;
        assetManager.loadThreadSafePart();
    }

    // Set preload to true if you want to load the asset immediately
    // before actual loading (e.g., to render a loading screen)
    Asset addAsset(Asset asset, string filename, bool preload = false)
    {
        if (preload)
            assetManager.preloadAsset(asset, filename);
        else
            assetManager.addAsset(asset, filename);
        return asset;
    }

    ImageAsset addImageAsset(string filename, bool preload = false)
    {
        ImageAsset img;
        if (assetManager.assetExists(filename))
            img = cast(ImageAsset)assetManager.getAsset(filename);
        else
        {
            img = New!ImageAsset(assetManager.imageFactory, assetManager.hdrImageFactory, assetManager);
            addAsset(img, filename, preload);
        }
        return img;
    }

    TextureAsset addTextureAsset(string filename, bool preload = false)
    {
        TextureAsset tex;
        if (assetManager.assetExists(filename))
            tex = cast(TextureAsset)assetManager.getAsset(filename);
        else
        {
            tex = New!TextureAsset(assetManager.imageFactory, assetManager.hdrImageFactory, assetManager);
            addAsset(tex, filename, preload);
        }
        return tex;
    }

    OBJAsset addOBJAsset(string filename, bool preload = false)
    {
        OBJAsset obj;
        if (assetManager.assetExists(filename))
            obj = cast(OBJAsset)assetManager.getAsset(filename);
        else
        {
            obj = New!OBJAsset(assetManager);
            addAsset(obj, filename, preload);
        }
        return obj;
    }

    TextAsset addTextAsset(string filename, bool preload = false)
    {
        TextAsset text;
        if (assetManager.assetExists(filename))
            text = cast(TextAsset)assetManager.getAsset(filename);
        else
        {
            text = New!TextAsset(assetManager);
            addAsset(text, filename, preload);
        }
        return text;
    }

    BinaryAsset addBinaryAsset(string filename, bool preload = false)
    {
        BinaryAsset bin;
        if (assetManager.assetExists(filename))
            bin = cast(BinaryAsset)assetManager.getAsset(filename);
        else
        {
            bin = New!BinaryAsset(assetManager);
            addAsset(bin, filename, preload);
        }
        return bin;
    }

    PackageAsset addPackageAsset(string filename, bool preload = false)
    {
        PackageAsset pa;
        if (assetManager.assetExists(filename))
            pa = cast(PackageAsset)assetManager.getAsset(filename);
        else
        {
            pa = New!PackageAsset(this, assetManager);
            addAsset(pa, filename, preload);
        }
        return pa;
    }

    Material addMaterial()
    {
        return New!Material(assetManager);
    }

    Material addDecalMaterial()
    {
        auto mat = addMaterial();
        mat.blending = Transparent;
        mat.depthWrite = false;
        mat.culling = false;
        return mat;
    }

    Cubemap addCubemap(uint size)
    {
        return New!Cubemap(size, assetManager);
    }

    Entity addEntity(Entity parent = null)
    {
        Entity e = New!Entity(entityManager);
        if (parent)
            e.setParent(parent);
        return e;
    }

    Entity useEntity(Entity e)
    {
        entityManager.addEntity(e);
        return e;
    }

    Entity addEntityHUD(Entity parent = null)
    {
        Entity e = New!Entity(entityManager);
        e.layer = EntityLayer.Foreground;
        if (parent)
            e.setParent(parent);
        return e;
    }

    Camera addCamera(Entity parent = null)
    {
        Camera c = New!Camera(entityManager);
        if (parent)
            c.setParent(parent);
        return c;
    }

    Light addLight(LightType type, Entity parent = null)
    {
        Light light = New!Light(entityManager);
        if (parent)
            light.setParent(parent);
        light.type = type;
        return light;
    }

    Entity addDecal(Entity parent = null)
    {
        Entity e = New!Entity(entityManager);
        e.decal = true;
        e.drawable = decalShape;
        if (parent)
            e.setParent(parent);
        return e;
    }

    // Override me
    void beforeLoad()
    {
    }

    // Override me
    void onLoad(Time t, float progress)
    {
    }

    // Override me
    void afterLoad()
    {
    }

    // Override me
    void onUpdate(Time t)
    {
    }

    import std.stdio;

    void update(Time t)
    {
        processEvents();

        if (isLoading)
        {
            onLoad(t, assetManager.nextLoadingPercentage);
            isLoading = assetManager.isLoading;
        }
        else
        {
            if (!loaded)
            {
                assetManager.loadThreadUnsafePart();
                debug writeln("Scene loaded");
                loaded = true;
                afterLoad();

                onLoad(t, 1.0f);

                canRender = true;
            }

            onUpdate(t);

            foreach(e; entityManager.entities)
            {
                e.update(t);
            }
        }
    }
}

class EntityGroupSpatial: Owner, EntityGroup
{
    EntityManager entityManager;

    this(EntityManager entityManager, Owner owner)
    {
        super(owner);
        this.entityManager = entityManager;
    }

    int opApply(scope int delegate(Entity) dg)
    {
        int res = 0;
        auto entities = entityManager.entities.data;
        for(size_t i = 0; i < entities.length; i++)
        {
            auto e = entities[i];
            if (e.layer == EntityLayer.Spatial && !e.decal)
            {
                res = dg(e);
                if (res)
                    break;
            }
        }
        return res;
    }
}

class EntityGroupDecals: Owner, EntityGroup
{
    EntityManager entityManager;

    this(EntityManager entityManager, Owner owner)
    {
        super(owner);
        this.entityManager = entityManager;
    }

    int opApply(scope int delegate(Entity) dg)
    {
        int res = 0;
        auto entities = entityManager.entities.data;
        for(size_t i = 0; i < entities.length; i++)
        {
            auto e = entities[i];
            if (e.decal)
            {
                res = dg(e);
                if (res)
                    break;
            }
        }
        return res;
    }
}

class EntityGroupSpatialOpaque: Owner, EntityGroup
{
    EntityManager entityManager;
    bool dynamic = true;

    this(EntityManager entityManager, bool dynamic, Owner owner)
    {
        super(owner);
        this.entityManager = entityManager;
        this.dynamic = dynamic;
    }

    int opApply(scope int delegate(Entity) dg)
    {
        int res = 0;
        auto entities = entityManager.entities.data;
        for(size_t i = 0; i < entities.length; i++)
        {
            auto e = entities[i];
            if (e.layer == EntityLayer.Spatial && !e.decal)
            {
                bool opaque = true;
                if (e.material)
                    opaque = !e.material.isTransparent;

                if (opaque && e.dynamic == dynamic)
                {
                    res = dg(e);
                    if (res)
                        break;
                }
            }
        }
        return res;
    }
}

class EntityGroupSpatialTransparent: Owner, EntityGroup
{
    EntityManager entityManager;

    this(EntityManager entityManager, Owner owner)
    {
        super(owner);
        this.entityManager = entityManager;
    }

    int opApply(scope int delegate(Entity) dg)
    {
        int res = 0;
        auto entities = entityManager.entities.data;
        for(size_t i = 0; i < entities.length; i++)
        {
            auto e = entities[i];
            if (e.layer == EntityLayer.Spatial && !e.decal)
            {
                bool transparent = false;
                if (e.material)
                    transparent = e.material.isTransparent;

                if (transparent)
                {
                    res = dg(e);
                    if (res)
                        break;
                }
            }
        }
        return res;
    }
}

class EntityGroupBackground: Owner, EntityGroup
{
    EntityManager entityManager;

    this(EntityManager entityManager, Owner owner)
    {
        super(owner);
        this.entityManager = entityManager;
    }

    int opApply(scope int delegate(Entity) dg)
    {
        int res = 0;
        auto entities = entityManager.entities.data;
        for(size_t i = 0; i < entities.length; i++)
        {
            auto e = entities[i];
            if (e.layer == EntityLayer.Background)
            {
                res = dg(e);
                if (res)
                    break;
            }
        }
        return res;
    }
}

class EntityGroupForeground: Owner, EntityGroup
{
    EntityManager entityManager;

    this(EntityManager entityManager, Owner owner)
    {
        super(owner);
        this.entityManager = entityManager;
    }

    int opApply(scope int delegate(Entity) dg)
    {
        int res = 0;
        auto entities = entityManager.entities.data;
        for(size_t i = 0; i < entities.length; i++)
        {
            auto e = entities[i];
            if (e.layer == EntityLayer.Foreground)
            {
                res = dg(e);
                if (res)
                    break;
            }
        }
        return res;
    }
}

class EntityGroupLights: Owner, EntityGroup
{
    EntityManager entityManager;

    this(EntityManager entityManager, Owner owner)
    {
        super(owner);
        this.entityManager = entityManager;
    }

    int opApply(scope int delegate(Entity) dg)
    {
        int res = 0;
        auto entities = entityManager.entities.data;
        for(size_t i = 0; i < entities.length; i++)
        {
            auto e = entities[i];
            Light light = cast(Light)e;
            if (light)
            {
                res = dg(e);
                if (res)
                    break;
            }
        }
        return res;
    }
}

class EntityGroupSunLights: Owner, EntityGroup
{
    EntityManager entityManager;

    this(EntityManager entityManager, Owner owner)
    {
        super(owner);
        this.entityManager = entityManager;
    }

    int opApply(scope int delegate(Entity) dg)
    {
        int res = 0;
        auto entities = entityManager.entities.data;
        for(size_t i = 0; i < entities.length; i++)
        {
            auto e = entities[i];
            Light light = cast(Light)e;
            if (light)
            {
                if (light.type == LightType.Sun)
                {
                    res = dg(e);
                    if (res)
                        break;
                }
            }
        }
        return res;
    }
}

class EntityGroupAreaLights: Owner, EntityGroup
{
    EntityManager entityManager;

    this(EntityManager entityManager, Owner owner)
    {
        super(owner);
        this.entityManager = entityManager;
    }

    int opApply(scope int delegate(Entity) dg)
    {
        int res = 0;
        auto entities = entityManager.entities.data;
        for(size_t i = 0; i < entities.length; i++)
        {
            auto e = entities[i];
            Light light = cast(Light)e;
            if (light)
            {
                if (light.type == LightType.AreaSphere ||
                    light.type == LightType.AreaTube ||
                    light.type == LightType.Spot)
                {
                    res = dg(e);
                    if (res)
                        break;
                }
            }
        }
        return res;
    }
}
