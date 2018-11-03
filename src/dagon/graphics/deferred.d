/*
Copyright (c) 2018 Timur Gafarov

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

module dagon.graphics.deferred;

import std.stdio;
import std.conv;

import dlib.core.memory;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.transformation;
import dlib.image.color;

import dagon.core.libs;
import dagon.core.ownership;
import dagon.core.interfaces;
import dagon.graphics.rc;
import dagon.graphics.gbuffer;
import dagon.graphics.shadow;
import dagon.graphics.light;
import dagon.graphics.screensurface;
import dagon.graphics.shapes;
import dagon.graphics.shaders.environmentpass;
import dagon.graphics.shaders.lightpass;
import dagon.resource.scene;

class DeferredEnvironmentPass: Owner
{
    EnvironmentPassShader shader;
    GBuffer gbuffer;
    CascadedShadowMap shadowMap;
    ScreenSurface surface;

    this(GBuffer gbuffer, CascadedShadowMap shadowMap, Owner o)
    {
        super(o);
        this.shader = New!EnvironmentPassShader(gbuffer, shadowMap, this);
        this.gbuffer = gbuffer;
        this.shadowMap = shadowMap;
        this.surface = New!ScreenSurface(this);
    }

    void render(RenderingContext* rc2d, RenderingContext* rc3d)
    {
        shader.bind(rc2d, rc3d);
        surface.render(rc2d);
        shader.unbind(rc2d, rc3d);
    }
}

class DeferredLightPass: Owner
{
    LightPassShader shader;
    GBuffer gbuffer;
    ShapeSphere lightVolume;

    this(GBuffer gbuffer, Owner o)
    {
        super(o);
        this.shader = New!LightPassShader(gbuffer, this);
        this.gbuffer = gbuffer;
        this.lightVolume = New!ShapeSphere(1.0f, 8, 4, false, this);
    }

    void render(Scene scene, RenderingContext* rc2d, RenderingContext* rc3d)
    {
        glDisable(GL_DEPTH_TEST);
        glDepthMask(GL_FALSE);

        glEnable(GL_CULL_FACE);
        glCullFace(GL_FRONT);

        glEnablei(GL_BLEND, 0);
        glEnablei(GL_BLEND, 1);
        glEnablei(GL_BLEND, 4);
        glBlendFunci(0, GL_ONE, GL_ONE);
        glBlendFunci(1, GL_ONE, GL_ONE);

        // TODO: don't rebind the shader each time,
        // use special method to update light data
        foreach(light; scene.lightManager.lightSources.data)
        {
            shader.light = light;
            shader.bind(rc2d, rc3d);
            lightVolume.render(rc3d);
            shader.unbind(rc2d, rc3d);
        }

        glDisablei(GL_BLEND, 0);
        glDisablei(GL_BLEND, 1);

        glCullFace(GL_BACK);
        glDisable(GL_CULL_FACE);

        glDepthMask(GL_TRUE);
        glEnable(GL_DEPTH_TEST);
    }
}
