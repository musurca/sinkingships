pico-8 cartridge // http://www.pico-8.com
version 18
__lua__
-- sinking ships
-- by musurca

--LIGHTING 
function initlightlut()
	lightlut={
 		unpack("0, 0,0,0,0"),
 		unpack("1, 0,0,0,0"),
 		unpack("2, 0,0,0,0"),
 		unpack("3, 0,0,0,0"),
 		unpack("4, 2,0,0,0"),
 		unpack("5, 5,1,0,0"),
 		unpack("6, 5,1,0,0"),
 		unpack("7, 6,5,1,0"),
 		unpack("8, 8,2,2,0"),
 		unpack("9, 4,2,0,0"),
		unpack("10, 10,10,10,0"),
		unpack("11, 3,0,0,0"),
		unpack("12,13,13,1,0"),
		unpack("13, 5,1,0,0"),
		unpack("6, 5,1,0,0"),
		unpack("15, 4,2,0,0")}
	
	local memstart=0x4300
	for j=1,5 do
		for k=1,16 do
			poke(memstart,lightlut[k][j])
			memstart+=1
		end
	end
end

cur_lightindex=1
function light(t)
 local index=band((1-t)*4.5,0xffff)
 if(index==cur_lightindex) return
 cur_lightindex=index
 memcpy(0x5f00,0x4300+0x10*index,0x10)
end

-- UTILITY FUNCTIONS

function nullfunc() end

function char(str,i)
	return sub(str,i,i)
end

function matchstr(c,str)
	for i=1,#str do
		if(char(str,i)==c) return i
	end
	return false
end

digits="0123456789"
function unpack(str)
	local arr,buffer={},""

	local function pushelement()
		if(matchstr(char(buffer,#buffer),digits)) buffer=tonum(buffer)
		add(arr,buffer)
		buffer=""
	end

	for i=1,#str do
		local c=char(str,i)
		if c=="," then
			pushelement()
		else
			buffer=buffer..c
		end
	end
	pushelement()
	return arr
end

function arrayrnd(arr)
	return arr[flr(rnd(#arr))+1]
end

function rndspan(n)
	return rnd(n)-shr(n,1)
end

function deletelist(list,todel)
	for i=1,#todel do
		del(list,todel[i])
	end
end

function adist(a,b)
	local a0,b0=abs(a),abs(b)
	return max(a0,b0)*0.9609+min(a0,b0)*0.3984
end

function normalize(x,y)
	local d=adist(x,y)
	if(d>0) return x/d,y/d,d
	return x,y,0
end

function getcamerapos()
	return peek2(0x5f28),peek2(0x5f2a)
end

--EVENT (MANAGED COROUTINE) SYSTEM

event_list={}
function make_event(func, args)
	add(event_list,{cocreate(func),args})
end

-- PROJECTILES / CANNONBALLS / ETC

function make_cannonball(cshooter,x,y,vx,vy,dist)
	local plist,p=particles[2],{x,y,1,0,0.6,vx,vy,0,0.991,false,dist,0,false,false,false,x,y,particle=true,shooter=cshooter}
	--[[
	p[1]=x
	p[2]=y
	p[3]=1
	p[4]=0
	p[5]=0.6
	p[6]=vx
	p[7]=vy
	p[8]=0
	p[9]=0.991
	p[10]=false
	p[11]=dist
	p[12]=0
	p[13]=false
	p[14]=false
	p[15]=false

	p[16]=x
	p[17]=y
	]]--
	--p.particle,p.shooter=true,shooter
	
	projectiles[#projectiles+1],plist[#plist+1],nonwater_objects[#nonwater_objects+1]=p,p,p
end

function update_projectiles()
	local proj,to_del,p,s,hitSide,t,realx,realy,prevx,prevy,hitx,hity=projectiles,{}
	for i=1,#proj do
		p=proj[i]
		realx,realy,prevx,prevy=p[1],p[2]+p[3],p[16],p[17]+p[3]
		-- check for hits
		for i=1,#ships do
			s=ships[i]
			if s != p.shooter and s.height < 2 then
				hitSide,t=collision_line_ship(s,prevx,prevy,realx,realy)
				if hitSide != side_none  then 
					-- it's a hit!
					hitx,hity=prevx + t * (realx-prevx), prevy + t * (realy-prevy)

					sfx(3)
					damage_ship(s,10,hitSide,hitx,hity)

					to_del[#to_del+1],p[11]=p,0 -- let the particle manager destroy it
					goto skiploop
				end
			end
		end
		if p[11]<1 then					 
			--water splash
			make_particle(part_water,
						  p[1],p[2],0,
						  7,0.5,0,0,0,1,false,10,0.1,false,false,false)
			to_del[#to_del+1]=p
		end
		p[16],p[17]=p[1],p[2]
		::skiploop::
	end
	deletelist(projectiles,to_del)
end

--EVENT DEFINITIONS

broad_left,broad_none,broad_right=-1,0,1
function evt_broadside(args)
	local ship=args[1]
	
	if(ship.health <= 0) return
	if(ship.reloadcounter>0) return

	local broaddir,ctime,stype,basesmoketime,vecx,vecy,k,crossvecx,crossvecy,momentx,momenty=args[2],mid(0,1,args[3]/120),ship.shiptype,600
	if(timeofday==time_night) basesmoketime/=2

	ship.reloadcounter=stype.reloadtime

	sfx(stype.gunsnd)

	broadtime=max(20,stype.maxrange*ctime)

	ship.firing=broaddir
	for i=1,stype.guns do
		k=0.6*(1+(stype.guns/2)-i)
		crossvecx,crossvecy,momentx,momenty=ship.crossx*broaddir,ship.crossy*broaddir,ship.momentx,ship.momenty
		vecx,vecy=crossvecx*3.5,crossvecy*3.5
		vecx+=ship.dirx*k
		vecy+=ship.diry*k
		-- flash
		make_particle(part_air,
					  ship[1]+vecx, --x
				 	  ship[2]+vecy, --y
					  1,            --z
					  10,			--color
					  1+rnd(1),			--size
					  0, 0, 0,	--vec --0.5
					  0.95,
					  false,
					  3,
					  0.1,
					  false,
					  false,
					  false)
		
		make_cannonball(ship,
						ship[1]+vecx*2+rndspan(6),
						ship[2]+vecy*2+rndspan(6),
						crossvecx*2+momentx, crossvecy*2+momenty, broadtime+rndspan(0.1*broadtime))

		--smoke
		for i=1,3 do
		make_particle(part_air,
					 ship[1]+vecx*1.5+rndspan(4.5),
					 ship[2]+vecy*1.5+rndspan(4.5),
					 1.1,
					 5,
					 3,
					 momentx+crossvecx*rnd(2)+rndspan(0.5),momenty+crossvecy*rnd(2)+rndspan(0.5),0.02,
					 0.7,
					 false,
					 basesmoketime+rndspan(150),
					 0.01,
					 true,
					 true,
					 true)
		end
		for i=1,12 do
			yield()
		end
	end
	ship.firing=broad_none
end

waterclut=unpack("12,12,12,7,7")
function evt_shipwake(args)
	local ship,clut=args[1],waterclut

	while ship.health > 0 do
		moment=ship.moment
		if moment > 0.1 then
			local sx,sy=ship[1],ship[2]
			local dirx,diry,crossx,crossy,sign=ship.dirx,ship.diry,ship.crossx,ship.crossy,sgn(rndspan(2))
			if 0.5+sin((2+moment)*t()/1.5) > 0  then 
				make_particle(part_water,
							  sx+4.25*dirx+sign*1.25*crossx+rndspan(1),
							  sy+4.25*diry+sign*1.25*crossy+rndspan(1),
							  0,
							  arrayrnd(clut),
							  0.5,
							  1.5*sign*crossx*moment,
							  1.5*sign*crossy*moment,
							  0,
							  0.96,
							  false,
							  40+rndspan(20),
							  0,false,false,true)
			end
			if rnd()>0.5 then 
				make_particle(part_water,
						  	  sx-4*dirx,sy-4*diry,0,
						  	  arrayrnd(clut),0.5,rndspan(0.2),rndspan(0.2),0,0.99,false,100+rndspan(20),0,false,false,false)
			end
		end
		yield()
		yield()
		yield()
	end
end

function evt_enc(args)
	msg_show=true
	for i=1,240 do yield() end
	msg_show=false
end

function evt_spawnship(args)
	local ship=p0.ship
	local sx,sy=ship[1],ship[2]

	--recover half max-health after defeating a ship
	if(ship.health>0) ship.health = min(ship.shiptype.health,ship.health+shiptypes[demo_types[p1.shipsel]].health/3)

	if(surv_wave>0) for i=1,180 do yield() end

	--spawn the next ship
	surv_wave+=1
	rseed=rnd(32700)
	srand(surv_wave)
	local ang,range=rnd(),90+rnd(90)
	for i=1,rnd(10) do toggle_p1name() toggle_p1ship() end
	p1.ship=make_ship(demo_types[p1.shipsel],sx+range*cos(ang),sy+range*sin(ang),rnd(),french,true)
	srand(rseed)
	make_event(evt_enc)
end

--killflash=false
function evt_killship(args)
	local ship,clut=args[1],waterclut

	if game_phase==phase_game then -- ignore in demo mode
		if p0.ship==ship or game_mode!=mode_surv then
			make_event(evt_endgame)
		else
			music(7,0,8)
			make_event(evt_spawnship)
		end
	end

	sfx(12)
	killflash=true

	--sink the ship
	ship.z,ship.helm=0,rndspan(0.9)
	while ship.height<8 do
		ship.height+=0.5
		for i=1,60 do
			if rnd()>0.3 then
				make_particle(part_water,
						  	  ship[1]+ship.momentx,ship[2]+ship.momenty,0,
						  	  arrayrnd(clut),0.5,rndspan(0.35),rndspan(0.35),0,0.99,false,100+rndspan(20),0,false,false,false)
			end
			yield()
		end
	end

	remove_ship(ship)
end

function evt_endgame(args)
	if p0.ship.health <= 0 and p1.ship.health<= 0 then
		winner = nil
	elseif p0.ship.health <= 0 then
		winner = p1
	else
		winner = p0
	end

	if game_mode==mode_surv or game_mode==mode_2p or winner==p0 then
		music(4)
	else
		music(0)
	end
	
	for i=1,240 do yield() end
	game_phase=phase_endgame
	menu_set(p0,endgame_menu)
end

waveclut=unpack("12,12,7")
function evt_waves(args)
	local wclut,range=waveclut
	while true do
		range=1.333*128/zoom_lvl
		make_particle(part_water,
					  camerax+rndspan(range),cameray+rndspan(range),0,
					  arrayrnd(wclut),0.5,0.05*wx,0.05*wy,0,1,false,35,0,true,false,false)
		yield()
		yield()
		yield()
	end
end

function evt_changewind(args)
	local wrange=enc_weather_ranges[enc_weather]
	targang,targspd=rnd(),flr(wrange[1]+rnd(wrange[2]-wrange[1]))
	local oldang,oldspd=wangle,wspeed
	for i=1,120 do
		wangle,wspeed = oldang + i*(targang-oldang)/120, oldspd + i*(targspd-oldspd)/120
		wx,wy=cos(wangle),sin(wangle)
		yield()
	end
end

-- PARTICLE SYSTEM

nonwater_objects,particles,part_water,part_air={},{},1,2

function make_particle(ptype,x,y,z,c,sz,vx,vy,vz,decay,gravity,life,deltasz,trans,wind,lit)
	local plist,p=particles[ptype],{x,y,z,c,sz,vx,vy,vz,decay,gravity,life,deltasz,trans,wind,lit,particle=true,zsort=y+shl(z,7)}
	--[[
	p[1]=x
	p[2]=y
	p[3]=z
	p[4]=c
	p[5]=sz
	p[6]=vx
	p[7]=vy
	p[8]=vz
	p[9]=decay
	p[10]=gravity
	p[11]=life
	p[12]=deltasz
	p[13]=trans
	p[14]=wind
	p[15]=lit
	]]--
	--p.particle,p.zsort=true,y+shl(z,7)
	
	plist[#plist+1]=p
	--if an air particle, add to general list for sorting
	if(ptype==part_air) nonwater_objects[#nonwater_objects+1]=p
end

-- determines nearest ship firing for lighting
function nearest_ship_firing(px,py,thresh)
	local dist,ret,s,d=thresh,nil
	for i=1,#ships do
		s=ships[i]
		if s.firing!=broad_none then
			d=adist(s[1]-px,s[2]-py)
			if (d<thresh) dist,ret=d,s
		end
	end
	return ret,dist
end

transpat={0b1010010110100101.1,0b101101001011010.1}
function draw_display_list(nwo,sort)
	--insertion sort list by ascending (y + z*128)
	if sort then
		local k,prevk
		for n=2,#nwo do
      	 	k=n
			prevk=k-1
     	  	while k>1 and nwo[k].zsort<nwo[prevk].zsort do
     	      	nwo[k],nwo[k-1]=nwo[k-1],nwo[k]
     	      	k-=1
     	  	end
		end
	end

	--now draw it	
	local camx,camy=getcamerapos()
	local tpat,zoom,isnight,p,nx,ny,sz,fship,fdist,col,icol,prevcol,clut,clipx,clipy=transpat,zoom_lvl,timeofday==time_night
	for i=1,#nwo do
		p=nwo[i]
		if p.particle then
			nx,ny,sz,col=(p[1]-63)*zoom+63,(p[2]-p[3]-63)*zoom+63,p[5]*zoom,p[4]
			clipx,clipy=nx-camx,ny-camy
		 	--if clipx+sz>-1 and clipx-sz<128 and clipx+sz>-1 and clipy-sz<128 then
			if band(bor(clipx+sz, clipy+sz), 0xff80)==0 and band(bor(clipx-sz, clipy-sz), 0xff80)==0 then
				--set light
				fship=nil
				if p[15] and isnight then --particle can be lit -- slooow
					fship,fdist=nearest_ship_firing(p[1],p[2],75)
					if fship then
						clut=lightlut[col+1]
						prevcol=peek(0x5f00+col)
						icol=clut[6-band(5*(0.2+min(0.8,rnd(0.05)+15/(fdist+0.01))),0xffff)]
						poke(0x5f00+col,icol)
					end
				end
			
				if sz < 1.5 then
					--if (sz>0.5) pset(nx,ny,col)
					pset(nx,ny,col)
				else
					if(p[13]) fillp(tpat[flr(nx)%2+1])
					circfill(nx,ny,flr(sz),col)
					if(p[13]) fillp()
				end

				--reset light
				if(fship) poke(0x5f00+col,prevcol)
			end
		else
			draw_ship(p)
		end
	end
end

--FONT (based on @zep's 5x6 font)
align_left,align_center=0,1
fontchars="01234567890ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz,.?!\"&();:'-"
function pr(str,x,y,col,align)
	align,col=align or align_center,col or 7
	local sx,sy=getcamerapos()
	sx,sy=sx+x,sy+y
	if(align==align_center) sx=sx-#str*3
	local sx0,bgcol,prevcol,prevbgcol=sx,timeofday==time_night and 2 or 0,peek(0x5f07),peek(0x5f00)
	pal(7,col)
	pal(0,bgcol)
	for p =1,#str do
		local c=char(str,p)
		if c=="\n" then
			sy+=10 sx=sx0
		elseif c==" " then
			sx+=6
		else
			local index=matchstr(c,fontchars)-1

			local sprx,spry,h=index%21*6,93+flr(index/21)*9,9
			if(spry+h >127) h=127-spry
			sspr(sprx,spry,5,h,sx,sy)
			sx+=6
		end
	end
	pal(0,prevbgcol)
	pal(7,prevcol)
end

--VOXEL CREATION/RENDERING

function build_voxel(sprindex,layers,w,h,offx,offy)
	local halfw,halfh,vox,c=w/2,h/2,{}
	for i=sprindex,sprindex+layers-1 do
		for y=0,h-1 do
			for x=0,w-1 do
				c=sget((sprindex%16)*8+(i-sprindex)*w+x,flr(i/16)*8+y)
				if(c!=14) add(vox,{x-halfw+offx,y-halfh+offy,i-sprindex,c})
			end
		end
	end
	return vox
end

function build_voxel_2x(sprindex,layers,w,h,offx,offy)
	local halfw,halfh,vox,vcol=w,h,{}
	
	local function addvoxel(u,v,l,k)
		add(vox, {u-halfw+offx,v-halfh+offy,l,k})
	end
	
	for count=sprindex,sprindex+layers-1 do
 		local soffx,soffy,sizex,sizey,a,b,c,d,e,f,g,h,i,e0,e1,e2,e3=(sprindex%16)*8+(count-sprindex)*w,flr(count/16)*8,w-1,h-1

		for y=0,sizey do
			for x=0,sizex do
				local vx,vy=soffx+x,soffy+y
				e=sget(vx,vy)
				a,b,c,d,f,g,h,i=e,e,e,e,e,e,e,e

				if(y>0) b=sget(vx,vy-1)
				if(y<sizey) h=sget(vx,vy+1)

				if x>0 then 
					d=sget(vx-1,vy)
					if(y>0) a=sget(vx-1,vy-1)
    				if(y<sizey) g=sget(vx-1,vy+1)
				end

				if x<sizex then
    				f=sget(vx+1,vy)
					if(y>0) c=sget(vx+1,vy-1)
					if(y<sizey) i=sget(vx+1,vy+1)
				end

				e0,e1,e2,e3=e,e,e,e

				if b!=h and d!=f then
					if(d==b) e0=d
					if(b==f) e1=f
					if(d==h) e2=d
					if(h==f) e3=f
				end

				local x0,y0,z=x*2,y*2,count-sprindex
				if(e0!=14) addvoxel(x0,  y0,  z,e0)
				if(e1!=14) addvoxel(x0+1,y0,  z,e1)
				if(e2!=14) addvoxel(x0,  y0+1,z,e2)
				if(e3!=14) addvoxel(x0+1,y0+1,z,e3)
			end
 		end
	 end
	return vox
end

--todo: try using a fill pattern for some colors by lut
--              0 1 2 3 4  5  6  7  8  9 10 11 12 13 14 15
shadlut=unpack("0,4,2,4,2, 4, 4,14, 8, 4, 4, 4,12, 4, 4, 4")
function draw_voxel(vox,sx,sy,angle,zoom,zstart)
	zoom,zstart=zoom or 1,zstart or 0
	zcheck=zstart-1
	local cang,lut,p,x,y,z,a,b,c,offc=angle+0.25,shadlut
	local dirx,diry=-cos(cang),-sin(cang)
	if zstart > 0 then
		if zoom>1 then
			local zfrac=zstart%1
			zcheck*=2
			zstart,zoom=flr(zstart*2),1
			for i=1,#vox do
				p=vox[i]
				x,y,z,c=p[1]*zoom,p[2]*zoom,p[3]*2,p[4]
				if z>zcheck then
					a,b,offc=sx+x*dirx-y*diry,sy+x*diry+y*dirx-z+zstart,lut[c+1]
					if zfrac>0 and z==(zstart+1) then
						pset(a,b+1,c)
						pset(a+1,b+1,offc)
					else
						rectfill(a,b,a,b+1,c)
						rectfill(a+1,b,a+1,b+1,offc)
					end
				end
			end
		else
			zstart=flr(zstart)
			for i=1,#vox do
				p=vox[i]
				x,y,z,c=p[1]*zoom,p[2]*zoom,p[3]*zoom,p[4]
				if z>zcheck then
					a,b,offc=sx+x*dirx-y*diry,sy+x*diry+y*dirx-z+zstart,lut[c+1]
					pset(a,b,c)
					pset(a+1,b,offc)
				end
			end
		end
	else
		if zoom>1 then
			zoom=1
			for i=1,#vox do
				p=vox[i]
				x,y,z,c=p[1]*zoom,p[2]*zoom,p[3]*2,p[4]
				a,b,offc=sx+x*dirx-y*diry,sy+x*diry+y*dirx-z,lut[c+1]
				rectfill(a,b,a,b+1,c)
				rectfill(a+1,b,a+1,b+1,offc)	
			end
		else
			for i=1,#vox do
				p=vox[i]
				x,y,z,c=p[1]*zoom,p[2]*zoom,p[3]*zoom,p[4]
				a,b,offc=sx+x*dirx-y*diry,sy+x*diry+y*dirx-z,lut[c+1]
				pset(a,b,c)
				pset(a+1,b,offc)
			end
		end
	end
end

--PLAYER/AI SHIPS

shiptypes={}
function add_shiptype(args,ssailcurve,mdlargs)
	local sname,sprindex,layers,w,h,offx,offy,boundw,boundh=args[1],mdlargs[1],mdlargs[2],mdlargs[3],mdlargs[4],mdlargs[5],mdlargs[6],mdlargs[7],mdlargs[8]
	local ship={name=sname,
				desc=args[2],
				guns=args[3],
				gunsnd=args[7],
				mass=args[8],
				sailcurve=ssailcurve,
				maxrange=args[4],
				reloadtime=args[5],
				health=args[6],
				model=build_voxel(sprindex,layers,w,h,offx,offy),
				model2x=build_voxel_2x(sprindex,layers,w,h,offx,offy),
				oobb={-boundw/2,-boundh/2,boundw/2,boundh/2},
				radius=max(boundw/2,boundh/2)}
	shiptypes[sname]=ship
end

british,french=8,12

function make_ship(typename,x,y,ang,faction,isai)
	local stype=shiptypes[typename]
	local s={x,
			 y,
			 1,
			 shiptype=stype,
			 model=stype.model,
			 model2x=stype.model2x,
			 health=stype.health,
			 moment=0,
			 momentx=0,
			 momenty=0,
			 helm=0,
			 height=0,
			 angle=ang,
			 dirx=cos(ang),
			 diry=sin(ang),
			 faction=faction,
			 ai=isai or false,
			 aitick=0,
			 aistate=0,
			 particle=false,
			 firing=broad_none,
			 firedirection=broad_left,
			 reloadcounter=0,
			 light=0,
			 zsort=y+128}
	s.crossx,s.crossy=-s.diry,s.dirx

	add(nonwater_objects,s)
	add(ships,s)

	make_event(evt_shipwake,{s})

	return s
end

function remove_ship(s)
	s.health=0
	if (p0.ship == s) p0.ship = nil
	if (p1.ship == s) p1.ship = nil
	del(nonwater_objects,s)
	del(ships,s)
end

crunchlut=unpack("4,4,2,0")
function damage_ship(s, amt, side, hitx, hity)
	if(s.health <= 0) return

	if side==side_top then
		amt *= 1.75
	elseif side==side_bottom then
		amt *= 2.5
	else
		--vector to hit location
		local rhitx,rhity,mag=normalize(hitx-s[1],hity-s[2])

		--modulate damage by directness of hit
		--side_left defined as -1,side_right defined as 1
		local dot,prevamt = max(0,side*s.crossx*rhitx+side*s.crossy*rhity),amt
		amt = (0.5*prevamt) + 0.5*dot*prevamt
	end
	s.health -= amt

	local clut,mx,my=crunchlut,s.momentx,s.momenty
	for i=1,6 do
		make_particle(part_air,hitx,hity,1.1,arrayrnd(clut),0.6,mx+rndspan(0.2),my+rndspan(0.2),0.6+rnd(0.5),0.99,true,240,0,false,false,true)
	end

	if(s.health <= 0) make_event(evt_killship,{s})
end

function update_ship(s)
	s.angle+=max(0.325,3*s.moment)*s.helm*0.01
	
	s.dirx,s.diry=cos(s.angle),sin(s.angle)
	local dirx,diry=s.dirx,s.diry
	s.crossx,s.crossy=-diry,dirx
	local crossx,crossy=s.crossx,s.crossy

	if s.ai and s.health > 0 then
		local enemy,evecx,evecy,edist,aimdot,shotside=p0.ship,0,0,0
		if(s==enemy) enemy=p1.ship
		if enemy then
			evecx,evecy,edist=normalize(enemy[1]-s[1],enemy[2]-s[2])
			aimdot=crossx*evecx+crossy*evecy
			if s.reloadcounter==0 and enemy.health > 0 and edist < 0.75*s.shiptype.maxrange and abs(aimdot) > 0.9 and rnd()>0.1 then
				make_event(evt_broadside,{s,sgn(aimdot),120})
			end
		end

		if (edist > 250) s.aistate=1

		if s.aistate==1 then --start to chase enemy if too far away
			local bowdot=(dirx*evecx+diry*evecy+1)/2
			s.helm=-sgn(aimdot)*(1-bowdot)
			if (edist < 120) s.aistate=0
		elseif s.aitick<=0 then
			s.helm=rndspan(0.6)
			s.aitick=200+flr(rnd(40))
		end
		s.aitick-=1
	end

	local smomentx,smomenty,forcex,forcey,windx,windy,winddot=s.momentx,s.momenty,0,0,0,0,0

	--sails catch wind if ship is alive
	if s.health > 0 then
		local winddot,curve=mid(-1,0.9999,dirx*wx+diry*wy),s.shiptype.sailcurve
		local cindex,curveval=((winddot+1)/2)*(#curve-1)+1
		local cfrac=cindex%1
		cindex=flr(cindex)
		curveval=(1-cfrac)*curve[cindex]+cfrac*curve[cindex+1]
		winddot=curveval*wspeed/(s.shiptype.mass*1024)
		windx,windy=winddot*dirx,winddot*diry
	end

	--base external velocity is previous velocity plus acceleration due to wind
	forcex,forcey=smomentx+windx,smomenty+windy

	--calculate bow drag
	local drag=max(0,forcex*dirx+forcey*diry)
	drag=-0.05*drag*drag/2
	local winddragx,winddragy=drag*forcex,drag*forcey

	--calculate lateral drag
	drag=abs(forcex*crossx+forcey*crossy)
	drag=-0.75*drag*drag/2
	local latdragx,latdragy=drag*forcex,drag*forcey

	--apply countervailing forces and find final velocity vector
	forcex,forcey=forcex+winddragx+latdragx,forcey+winddragy+latdragy

	local oldsx,oldsy=s[1],s[2]
	s[1]+=forcex
	s[2]+=forcey
	s.zsort=s[2]+shl(s[3],7)

	local function normal_by_side(ship,side)
		if(side==side_top) return ship.dirx,ship.diry
		if(side==side_right) return ship.crossx,ship.crossy
		if(side==side_left) return -ship.crossx,-ship.crossy
		return -ship.dirx,-ship.diry
	end

	--check for collisions
	if s.health > 0 then
		local othership,collside,otherside
		for i=1,#ships do
			othership=ships[i]
			if s!=othership then
				collside,otherside=collision_ship_ship(s,othership)
				if collside != side_none then
					local otherforcex,otherforcey,damage,mass,omass=0,0,0,s.shiptype.mass,othership.shiptype.mass
					local normx,normy=normal_by_side(othership,otherside)
					
					local mvecx,mvecy,forcemag=normalize(forcex,forcey)
					if forcemag>0 then
						local invvecx,invvecy=-mvecx,-mvecy
						local dothit=invvecx*normx+invvecy*normy
						local reflectx,reflecty=2*dothit*normx-invvecx,2*dothit*normy-invvecy
					
						dothit=max(0,-dothit)		
						forcex += reflectx*dothit*forcemag
						forcey += reflecty*dothit*forcemag

						forcemag*=omass
						damage = dothit*forcemag

						otherforcex,otherforcey=-normx*dothit*forcemag,-normy*dothit*forcemag
					end

					local oforcex,oforcey=othership.momentx,othership.momenty
					local ofvecx,ofvecy,oforcemag=normalize(oforcex,oforcey)
					if oforcemag > 0 then
						local dotforce=min(1,max(0,ofvecx*normx+ofvecy*normy))
						forcex += dotforce*oforcex
						forcey += dotforce*oforcey

						oforcemag*=mass
						otherforcex += -normx*(1-dotforce)*oforcemag
						otherforcey += -normy*(1-dotforce)*oforcemag

						damage += dotforce*oforcemag
					end

					local vecx,vecy=othership[1]-s[1],othership[2]-s[2]

					--apply forces to both ships
					s[1],s[2]=oldsx+forcex,oldsy+forcey
					if othership.health > 0 then
						othership.momentx += otherforcex
						othership.momenty += otherforcey
						othership.moment = adist(othership.momentx,othership.momenty)
					end

					--apply damage
					sfx(11)
					damage*= 5
					if damage > 1 then
						local hitx,hity=s[1]+vecx/2,s[2]+vecy/2
						damage_ship(s,damage,otherside,hitx,hity)
						damage_ship(othership,damage, collside, hitx, hity)
					end
				end
			end
		end
	end

	--bake in momentum
	s.momentx,s.momenty,s.moment=forcex,forcey,adist(forcex,forcey)

	-- ship reload
	if(s.reloadcounter > 0) s.reloadcounter-=1

	--lighting contribution at night due to firing
	if s.firing != broad_none then
		s.light = rnd(0.5)
		if timeofday==time_night then
			--fake water lighting
			local sidemag=s.light*18
			make_particle(part_water,s[1]+sidemag*s.firing*crossx,s[2]+sidemag*s.firing*crossy,0,7,sidemag,0,0,0,1,false,1,0,false,false,false)
		end
	else
		s.light = 0
	end

	--helm control decay
	if( not s.ai ) s.helm*=0.95
end

function draw_ship(s)
	local model,nx,ny=(zoom_lvl>1) and s.model2x or s.model,(s[1]-63)*zoom_lvl+63,(s[2]-63)*zoom_lvl+63

	if timeofday==time_night then
		if s.firing!=broad_none then
			light(min(1,1-0.5+s.light*(s.firing*s.crossy+1)/2))
		else
			--local emit=0
			local fship,fdist=nearest_ship_firing(s[1],s[2],200)
			local emit=0
			if(fship) emit=min(0.6-rnd(0.3),rnd(0.05)+20/(fdist+0.01))
			light(0.2+emit)
		end
	else
		if s.firing != broad_none then
			local sidemag=s.light*12*zoom_lvl
			circ(nx+s.firing*sidemag*s.crossx,ny+s.firing*sidemag*s.crossy,sidemag,12)
		end
	end

	if(s.health > 0) pal(6,s.faction)
	draw_voxel(model,nx,ny,s.angle,zoom_lvl,s.height)
	pal(6,6)
	if(timeofday==time_night) light(0.2)
end

-- COLLISION DETECTION

side_none,side_left,side_right,side_top,side_bottom=0,-1,1,2,3

function collision_line_rect(x1, y1, x2, y2, rx, ry, rw, rh)
	
	local function collision_line_line(x1, y1, x2, y2, x3, y3, x4, y4)
		--find direction of the lines
		local ua,ub = ((x4-x3)*(y1-y3) - (y4-y3)*(x1-x3)) / ((y4-y3)*(x2-x1) - (x4-x3)*(y2-y1)),
					  ((x2-x1)*(y1-y3) - (y2-y1)*(x1-x3)) / ((y4-y3)*(x2-x1) - (x4-x3)*(y2-y1))

		--if ua and ub are between 0-1, lines are colliding
		if (ua >= 0 and ua <= 1 and ub >= 0 and ub <= 1) return true, min(ua,ub) --, x1 + (uA * (x2-x1)), y1 + (uA * (y2-y1))
		return false
	end

	--check if the line has hit any of the rectangle's sides
	local sideHit,near_t,t,hit=side_none,2

	--left
	hit,t = collision_line_line(x1,y1,x2,y2, rx,ry,rx, ry+rh)
	if hit then
		near_t=t
		sideHit=side_bottom --side_left
	end

	--right
	hit,t = collision_line_line(x1,y1,x2,y2, rx+rw,ry, rx+rw,ry+rh)
	if hit and t<near_t then
		near_t=t
		sideHit=side_top--side_right
	end

	--top
	hit,t = collision_line_line(x1,y1,x2,y2, rx,ry, rx+rw,ry)
	if hit and t<near_t then
		near_t=t
		sideHit=side_left--side_top
	end

	--bottom
	hit,t = collision_line_line(x1,y1,x2,y2, rx,ry+rh, rx+rw,ry+rh)
	if hit and t<near_t then
		near_t=t
		sideHit=side_right--side_bottom
	end

	return sideHit,near_t
end

function collision_line_ship(ship,x1,y1,x2,y2)
	local rad,sx,sy=ship.shiptype.radius,ship[1],ship[2]
	local cx1,cy1,cx2,cy2=x1-sx,y1-sy,x2-sx,y2-sy

	--this optimization is wrong in general but fine for limited time-step of this simulation
	if (adist(cx1,cy1) > rad and adist(cx2,cy2) > rad) return side_none,2

	-- transform line into coordinate space of ship's bounding box
	local oobb,cosang,sinang=ship.shiptype.oobb,ship.dirx,-ship.diry
	local tx1,ty1,tx2,ty2,bx,by,bw,bh=cx1*cosang-cy1*sinang,cx1*sinang+cy1*cosang,cx2*cosang-cy2*sinang,cx2*sinang+cy2*cosang,oobb[1],oobb[2],oobb[3]*2,oobb[4]*2
	
	return collision_line_rect(tx1,ty1,tx2,ty2,bx,by,bw,bh)
end

--returns [side hit on ship1],[side hit on ship2]
function collision_ship_ship(ship1,ship2)
	local rad1,rad2,sx1,sy1,sx2,sy2=ship1.shiptype.radius,ship2.shiptype.radius,ship1[1],ship1[2],ship2[1],ship2[2]

	if(adist(sx2-sx1,sy2-sy1) > (rad1+rad2)) return side_none,side_none

	--transform ship1's bounding box into coordinate system of ship2's bounding box
	local oobb1,oobb2,cosang,sinang=ship1.shiptype.oobb,ship2.shiptype.oobb,ship2.dirx,-ship2.diry
	local bx1,by1,bw1,bh1,bx2,by2,bw2,bh2=oobb1[1]+sx1,oobb1[2]+sy1,oobb1[3]*2,oobb1[4]*2,oobb2[1],oobb2[2],oobb2[3]*2,oobb2[4]*2

	local rx1,ry1,rx2,ry3=bx1-sx2,by1-sy2,(bx1+bw1)-sx2,(by1+bh1)-sy2
	local ry2,rx3,rx4,ry4=ry1,rx2,rx2,ry3

	local function rotpt(x,y)
		return x*cosang-y*sinang,x*sinang+y*cosang
	end
	local tx1,ty1=rotpt(rx1,ry1)
	local tx2,ty2=rotpt(rx2,ry2)
	local tx3,ty3=rotpt(rx3,ry3)
	local tx4,ty4=rotpt(rx4,ry4)

	--front
	local sidehit=collision_line_rect(tx1,ty1,tx2,ty2,bx2,by2,bw2,bh2)
	if(sidehit!=side_none) return side_top,sidehit
	--right
	sidehit=collision_line_rect(tx2,ty2,tx3,ty3,bx2,by2,bw2,bh2)
	if(sidehit!=side_none) return side_right,sidehit
	--rear
	sidehit=collision_line_rect(tx3,ty3,tx4,ty4,bx2,by2,bw2,bh2)
	if(sidehit!=side_none) return side_bottom,sidehit
	--left
	sidehit=collision_line_rect(tx4,ty4,tx1,ty1,bx2,by2,bw2,bh2)
	if(sidehit!=side_none) return side_left,sidehit

	return side_none,side_none
end

-- TIME OF DAY / WEATHER / WIND DIRECTION 

function clear_wind()
	wangle=rnd()
	wx,wy,wspeed=cos(wangle),sin(wangle),flr(6+rnd(10))
end

--todo: day/night cycle while fighting
time_night,time_day=0,1
timeofday=time_day
function set_timeofday(tod)
	timeofday=tod

	light(1) -- bad, but nec. for token-saving
	if(tod==time_night) light(0.2)
end

-- GAME INITIALIZATION 

mode_1p,mode_2p,mode_surv=1,2,3
game_mode=mode_1p

ships={}
function reset_game()
	--clear events
	event_list={}

	--clear particles
	if (particles[2]) deletelist(nonwater_objects,particles[2])
	particles[1],particles[2]={},{}

	--clear projectiles
	projectiles={}

	--clear ships
	for s in all(ships) do
		del(nonwater_objects,s)
	end
	ships,zoom_lvl={},1

	make_event(evt_waves)
end

demo_times,demo_types={time_day,time_night},unpack("sloop,xebec,brig,line")

function setup_demo_mode() 
	reset_game()
	clear_wind()
	p0.ship=make_ship(arrayrnd(demo_types),rnd(200),rnd(200),rnd(),british,true)
	p1.ship=make_ship(demo_types[flr(rnd(3))+1],rnd(200),rnd(200),rnd(),french,true)
	set_timeofday(arrayrnd(demo_times))
end

function setup_game(ai)
	game_phase,msg_show,surv_wave=phase_game,false,0
	menu_set(p0,nil)
	menu_set(p1,nil)
	reset_game()
	local pa,pr=0.5+rndspan(0.125),70+rnd(90)
	local px,py=pr*cos(pa),pr*sin(pa)
	p0.ship=make_ship(demo_types[p0.shipsel],px,py,rndspan(0.4),british,false)
	if game_mode==mode_surv then
		make_event(evt_spawnship)
	else
		p1.ship=make_ship(demo_types[p1.shipsel],-px,-py,0.5+rndspan(0.4),french,ai)
		make_event(evt_enc)
	end
	set_timeofday(demo_times[enc_time])
	make_event(evt_changewind)
end

function _init()
	initlightlut()
	--palt(0,false)
	--palt(14,true)
	pal(14,6)
	
	--menus/gui elements
	windarrow,listofnames,chooseshipmenu,commitmenu=build_voxel(40,5,5,16,1,0),unpack("ACHERON,ACHILLE,AIGLE,AJAX,ARGO,AQUILON,ARIADNE,BACCANTE,BELLONA,BERMUDA,BILLY-BOY,CAESAR,CALCUTTA,CANADA,CHARON,CIRCE,COLOSSUS,CULLODEN,CUTTY SARK,DART,DIADEM,DIANA,ESSEX,FLAMBEAU,GANGES,GIBRALTAR,GOLIATH,HARPY,HELLFIRE,HIBERNIA,ISIS,JAVA,JUPITER,LEANDER,LIVELY,MAJESTIC,MALTA,MANLY,MARS,NAIAD,NAMUR,NELSON,NEPTUNE,NYMPHE,ORION,PALLAS,PEGASUS,POLYCHREST,PROVIDENT,QUEEN,RENOWN,REPULSE,REQUIN,RIVOLI,ROMULUS,SATURN,SCIPION,SOPHIE,STATELY,ST.ALBANS,SUPERB,SURPRISE,TERROR,THALIA,THAMES,THESEUS,ULYSSES,VALIANT,VENUS,ZEPHYR"),{{"          ",toggle_ship},{"          ",toggle_name}},{{"          ",toggle_time},{"          ",toggle_wind},{"ENGAGE!",toggle_engage}}

	main_menu,enc1p_menu,enc1popo_menu,enc1pcom_menu,enc2p0_menu,enc2p1_menu,enc2pcom_menu,endgame_menu,surv_menu,survcom_menu=make_menu({{"1P Encounter",start_1p_encounter},{"2P Encounter",start_2p_encounter},{"Survival",start_survival}},13),make_menu(chooseshipmenu,14,back_to_title,nullfunc,switch_to_commit_menu1p,nullfunc,function(p) menu_set(p,enc1popo_menu)
	enc1popo_menu.selection=enc1p_menu.selection end),make_menu({{"          ",toggle_p1ship},{"          ",toggle_p1name}},14,back_to_title,nullfunc,switch_to_commit_menu1p,function(p) menu_set(p,enc1p_menu) enc1p_menu.selection=enc1popo_menu.selection end,nullfunc),make_menu(commitmenu,14,back_to_title,function(p) menu_set(p,enc1p_menu) end),make_menu(chooseshipmenu,14,back_to_title,nullfunc,function(p) menu_set(p,enc2pcom_menu) end),make_menu(chooseshipmenu,14),make_menu(commitmenu,14,back_to_title,function(p) menu_set(p,enc2p0_menu) end),make_menu({{"Replay",setup_game},{"Back to Menu",back_to_title}},14),make_menu(chooseshipmenu,14,back_to_title,nullfunc,function(p) menu_set(p,survcom_menu) end),make_menu({{"ENGAGE!",toggle_engage}},14,back_to_title,function(p) menu_set(p,surv_menu) end)
	
	--make models
	--name,desc,guns,maxrange,reloadtime,health,gunsnd,mass,curve,sprindex,layers,w,h,offx,offy,boundw,boundh
	add_shiptype(unpack("line,Man o'War,10,160,260,250,7,1.75"),
				 unpack("0, 0.25,  0.4, 0.55,  0.6, 0.75,  0.8, 0.82, 0.84, 0.86,  0.9, 0.95, 1.0"),
				 unpack("0,8,7,16,1,-1,16,8"))
	add_shiptype(unpack("brig,Brigantine,6,160,200,210,8,1.25"),
				 unpack("0, 0.25, 0.45,  0.6,  0.7,  0.8,  0.9, 0.92, 0.95,  1.0, 0.95, 0.92, 0.9"),
				 unpack("7,8,7,16,1,0,12,6"))
	add_shiptype(unpack("xebec,Xebec,4,140,150,180,9,0.7"),
				 unpack("0,  0.4,  0.6, 0.75,  0.8,  0.9,  1.0,  0.9,  0.8, 0.75,  0.5,  0.4, 0.3"),
				 unpack("32,8,3,16,1,0,12,4"))
	add_shiptype(unpack("sloop,Sloop,2,100,100,140,10,0.6"),
				 unpack("0,  0.6, 0.75,  0.8,  0.9,  0.9, 0.95, 0.96, 0.99,  1.0,  0.9, 0.85, 0.8"),
				 unpack("35,7,5,16,1,0,9,4"))

	--clear_players()
	players={}
	for i=1,2 do
		local p={ship=nil,
				 shipsel=1,
				 namesel=flr(rnd(#listofnames))+1,
				 charging=false,
				 chargeside=broad_left,
				 chargetimer=0,
				 curmenu=nil}
		players[i]=p
	end
	p0,p1=players[1],players[2]
	p0.faction,p1.faction=british,french
	toggle_name(p0) --nudge to ensure names aren't identical

	back_to_title()
end

function back_to_title()
	game_phase=phase_title
	menu_set(p0,main_menu)
	menu_set(p1,nil)
	setup_demo_mode()
end

-- CUSTOM INPUT HANDLER
input={unpack("0,0,0,0,0,0"),
	   unpack("0,0,0,0,0,0")}

function button_up(b,player)
	if( not player.ship ) return
	if( player.ship.ai ) return

	if player.charging and ((b==4 and player.chargeside==broad_left) or (b==5 and player.chargeside==broad_right)) then
		player.charging=false
		make_event(evt_broadside,{player.ship,player.chargeside,player.chargetimer})
		player.chargetimer=0
		sfx(6,-2)
	end
end

function button_down(b,player)
	if game_phase!=phase_game then
		local menuactions={menu_left,menu_right,menu_up,menu_down,menu_select,menu_back}
		if(b<4) sfx(1)
		if(player.curmenu) menuactions[b+1](player,player.curmenu)
		return
	end

	if( not player.ship ) return
	if( player.ship.ai ) return

	if (b==4 or b==5) and not player.charging then
		if player.ship.reloadcounter==0 then
			player.chargeside=b==4 and broad_left or broad_right
			player.charging=true
			player.chargetimer=0
			sfx(6)
		else
			sfx(1)
		end
	end
end

function button_held(b,player)
	if(not player.ship ) return
	if( player.ship.ai ) return

	if (player.charging and ((b==4 and player.chargeside==broad_left) or (b==5 and player.chargeside==broad_right))) player.chargetimer+=1

	if (b==0) player.ship.helm+=0.01
	if (b==1) player.ship.helm-=0.01
end

-- MAIN 60FPS UPDATE LOOP

function _update60()
	--small chance of a shift in the wind
	if (rnd() > enc_weather_changes[enc_weather]) make_event(evt_changewind)

	--INPUT DISPATCH
	for p=0,1 do
		for k=0,5 do
			if btn(k,p) then
				if not input[p+1][k+1] then
					--button down
					input[p+1][k+1]=true
					button_down(k,players[p+1])
				end
				button_held(k,players[p+1])
			elseif input[p+1][k+1] then
				--button up
				input[p+1][k+1]=false
				button_up(k,players[p+1])
			end
		end
	end

	--update ship simulation (and find centroid for camera)
	local centroidx,centroidy,d,to_del,dist,s=0,0,0,{}
	for i=1,#ships do
		s=ships[i]
		update_ship(s)
		if s==p0.ship or s==p1.ship then
			centroidx,centroidy=centroidx+s[1],centroidy+s[2]
			to_del[#to_del+1]=s
		end
	end
	centroidx,centroidy=centroidx/#to_del,centroidy/#to_del

	--CAMERA UPDATE
	-- find farthest ship from centroid
	for i=1,#to_del do
		s=to_del[i]
		dist=2*adist(s[1]-centroidx,s[2]-centroidy)
		if (dist>d) d=dist
	end
	to_del={}
	
	--determine appropriate zoom level for combat situation
	--d*=2
	if zoom_lvl==1 then
		if d>120 then
			zoom_lvl=0.5
		elseif d<50 and #ships<3 then
			zoom_lvl=2
		end
	elseif zoom_lvl==2 then
		if d>=64 then
			zoom_lvl=1
		end
	elseif zoom_lvl==0.5 then
		if d>250 then
			zoom_lvl=0.25
		elseif d<115 then
			zoom_lvl=1
		end
	else--if zoom_lvl==0.25 then
		if (d<240) zoom_lvl=0.5
	end
	
	if camerax then
		--smooth camera
		camerax,cameray=camerax+(centroidx-camerax)/24,cameray+(centroidy-cameray)/24
	else	
		camerax,cameray=centroidx,centroidy
	end
	camera(flr(camerax*zoom_lvl-63*zoom_lvl),flr(cameray*zoom_lvl-63*zoom_lvl))

	--EVENT UPDATE
	local e,cor={}
	for i=1,#event_list do
		e=event_list[i]
		cor=e[1]
		if costatus(cor) != 'dead' then
			coresume(cor,e[2])
		else
			add(to_del,e)
		end
	end
	--delete completed events
	deletelist(event_list,to_del)
	to_del={}

	--PARTICLE UPDATE
	local wat_p,air_p,wvecx,wvecy,p,vx,vy,vz,z,decay,life=particles[1],particles[2],wx*wspeed/256,wy*wspeed/256

	-- WATER PARTICLES: lowest layer, not sorted, no gravity
	for i=1,#wat_p do
		p=wat_p[i]
		life=p[11]
		if life>0 then
			vx,vy,decay=p[6],p[7],p[9]
			p[1]+=vx    --x
			p[2]+=vy    --y
			p[5]+=p[12] --delta size

			vx*=decay
			vy*=decay
			life-=1
				
			p[6],p[7],p[11]=vx,vy,life
		else
			to_del[#to_del+1]=p
		end
	end
	deletelist(wat_p,to_del)
	to_del={}
	
	--AIR PARTICLES: sorted, consider gravity, remove from all objects when dead
	for i=1,#air_p do
		p=air_p[i]
		life=p[11]
		if life>0 then
			z,vx,vy,vz,decay=p[3],p[6],p[7],p[8],p[9]
			if(p[10]) vz -= 0.03 --g 
			z+=vz
			if z<0 then
				to_del[#to_del+1]=p
			else
				if p[14] then
					p[1]+=vx+wvecx
					p[2]+=vx+wvecy --this is a bug, but i prefer it
				else
					p[1]+=vx
					p[2]+=vy
				end
				p[5]+=p[12]

				vx*=decay
				vy*=decay
				vz*=decay
				life-=1
			
				p[3],p[6],p[7],p[8],p[11],p.zsort=z,vx,vy,vz,life,p[2]+shl(z,7)
			end
		else
			to_del[#to_del+1]=p
		end
	end
	deletelist(air_p,to_del)
	deletelist(nonwater_objects,to_del)

	update_projectiles()
end

-- GAME PHASES
phase_title,phase_enc1p,phase_enc2p,phase_surv,phase_game,phase_endgame=0,1,2,3,4,5

function make_menu(options,mspacing,mbackfunc,mupfunc,mdownfunc,mleftfunc,mrightfunc)
	mleftfunc,mrightfunc,mbackfunc,mupfunc,mdownfunc=mleftfunc or nullfunc,mrightfunc or nullfunc,mbackfunc or nullfunc,mupfunc or nullfunc,mdownfunc or nullfunc
	local m,w={spacing=mspacing,
			 selection=1,
			 backfunc=mbackfunc,
			 leftfunc=mleftfunc,
			 rightfunc=mrightfunc,
			 upfunc=mupfunc,
			 downfunc=mdownfunc,
			 active=false,
			 player=nil},0
	for i=1,#options do
		if(#options[i][1] > w) w=#options[i][1]
		m[i]=options[i]
	end
	m.items,m.width=#options,w*6
	return m
end

function menu_draw(menu,x,y)
	local sy,w=y,menu.width/2+1
	local cx,cy=getcamerapos()
	for i=1,menu.items do
		if(menu.selection==i and menu.active) rect(x+cx-w-1,sy+cy-2,x+w+cx-1,sy+cy+9,7)
		pr(menu[i][1],x,sy)
		sy+=menu.spacing
	end
end

function menu_set(player,menu)
	if(player.curmenu) player.curmenu.active=false
	player.curmenu=menu
	if(menu) menu.active=true
end

function menu_back(player,menu)
	sfx(2)
	menu.backfunc(player,menu)
end

function menu_left(player,menu)
	menu.leftfunc(player,menu)
end

function menu_right(player,menu)
	menu.rightfunc(player,menu)
end

function menu_up(player,menu)
	menu.selection-=1
	if menu.selection<1 then
		menu.selection=1
		if(menu.upfunc!=nullfunc) menu.upfunc(player)
	end
end

function menu_down(player,menu)
	menu.selection+=1
	if menu.selection>menu.items then
		menu.selection=menu.items
		if(menu.downfunc!=nullfunc) menu.downfunc(player)
	end
end

function menu_select(player,menu)
	sfx(0)
	menu[menu.selection][2](player)
end

function switch_to_commit_menu1p(player)
	menu_set(player,enc1pcom_menu)
end

function toggle_ship(player)
	player.shipsel+=1
	if(player.shipsel > #demo_types) player.shipsel=1
end

function toggle_p1ship(player)
	toggle_ship(p1)
end

function toggle_name(player)
	player.namesel+=1
	if(player.namesel>#listofnames) player.namesel=1
	if(p0.namesel==p1.namesel) toggle_name(player)
end

function toggle_p1name(player)
	toggle_name(p1)
end

enc_weather,enc_weather_names,enc_weather_ranges,enc_weather_changes,enc_time,enc_time_names=1,unpack("Calm Seas,Rough Seas,Gale"),{{6,12},{14,20},{12,30}},unpack("0.9999,0.9995,0.999"),1,unpack("Day,Night")

function toggle_time()
	enc_time+=1
	if(enc_time>2) enc_time=1
end

function toggle_wind()
	enc_weather+=1
	if(enc_weather>3) enc_weather=1
end

function toggle_engage(player)
	local ai=true
	if(game_phase==phase_enc2p) ai=false
	setup_game(ai)
end

function start_1p_encounter(player)
	game_mode,game_phase,enc_weather=mode_1p,phase_enc1p,1
	menu_set(player,enc1p_menu)
end

function start_2p_encounter(player)
	game_mode,game_phase=mode_2p,phase_enc2p
	menu_set(p0,enc2p0_menu)
	menu_set(p1,enc2p1_menu)
end

function start_survival(player)
	game_mode,game_phase,enc_weather,enc_time,p1.shipsel=mode_surv,phase_surv,2,1,1
	menu_set(p0,surv_menu)
end

-- MAIN RENDERING LOOP
dirarray,titles=unpack("E,ENE,NE,NNE,N,NNW,NW,WNW,W,WSW,SW,SSW,S,SSE,SE"),unpack("SHIP'S BOY.,ABLE SEAMAN.,WARRANT.,MIDSHIPMAN.,ENSIGN.,LIEUTENANT.,MASTER.,CAPTAIN.,POST-CAPTAIN.,COMMODORE.,REAR ADMIRAL.,VICE ADMIRAL.,FLEET ADMIRAL.,PRIME MINISTER.,NATIONAL HERO.,LORD OF THE SEA.")
function draw_gamephase_hud()
	local cx,cy=getcamerapos()
	palt(14,true)

	local function draw_player_shipsel(player,name,x,y)
		pr(name,x+32,y)
		local px,py,shiptype=x+cx,y+cy+14,shiptypes[demo_types[player.shipsel]]
		rectfill(px+4,py-5,px+60,py-5,player.faction)
		spr(44,px,py,4,4)
		rectfill(px+34,py,px+60,py+32,1)
		rect(px+34,py,px+60,py+32,7)
		pal(6,player.faction)
		draw_voxel(shiptype.model,47+px,py+18,t()/4)
		pal(6,6)
		pr(shiptype.desc,x+32,y+50,player.faction)
		pr(listofnames[player.namesel],x+32,y+64,player.faction)

		local curve=shiptype.sailcurve
		local function draw_curve_line(csign)
			local cang,prt,pd,cval=0.04167,16+px,16+py,14.5*curve[2]
			line(prt,pd,prt+csign*cval*sin(-cang),pd-cval*cos(-cang),7)
			for i=3,#curve do
				cang,cval=cang+0.04167,14.5*curve[i]
				line(prt+csign*cval*sin(-cang),pd-cval*cos(-cang))
			end
		end
		draw_curve_line(1)
		draw_curve_line(-1)
	end

	local function draw_game_settings(z)
		pr(enc_time_names[enc_time],63,z)
		pr(enc_weather_names[enc_weather],63,z+14)
	end

	if game_phase==phase_title then
		sspr(0,48,107,44,10+cx,8+cy)
		menu_draw(main_menu,63,80)
		print("                      BY MUSURCA",cx,cy+122,5)
	elseif game_phase==phase_enc1p then
		menu_draw(enc1p_menu,32,52)
		menu_draw(enc1popo_menu,97,52)
		menu_draw(enc1pcom_menu,63,85)
		draw_player_shipsel(p0,"Player", 1,2)
		draw_player_shipsel(p1,"Opponent", 65,2)
		draw_game_settings(85)
	elseif game_phase==phase_enc2p then
		menu_draw(enc2p0_menu,32,52)
		menu_draw(enc2p1_menu,97,52)
		menu_draw(enc2pcom_menu,63,85)
		draw_player_shipsel(p0,"Player 1", 1,2)
		draw_player_shipsel(p1,"Player 2", 65,2)
		draw_game_settings(85)
	elseif game_phase==phase_endgame then
		if game_mode==mode_surv then
			pr("The "..shiptypes[demo_types[p0.shipsel]].desc,63,4)
			pr(listofnames[p0.namesel],63,16,british)
			pr("dispatched",63,28)
			pr((surv_wave-1).." ship"..(surv_wave==2 and "" or "s")..",",63,40)
			pr("earning the title",63,52)
			pr(titles[min(surv_wave,16)],63,64,british)
		else
			if winner==nil then
				pr("DRAW",63,32)
			else
				local object,endstr=p0,"Defeat for"
				if game_mode==mode_2p or winner==p0 then
					object,endstr=winner,"Victory to"
				end
				pr(endstr,63,20)
				pr("the "..listofnames[object.namesel].."!",63,32,object.faction)
			end
		end
		menu_draw(endgame_menu,63,85)
 elseif game_phase==phase_surv then
		menu_draw(surv_menu,62,62)
		menu_draw(survcom_menu,62,95)
		draw_player_shipsel(p0,"Player", 30,12)
	else
		if msg_show then
			if game_mode==mode_surv then
				pr(surv_wave..".",63,8)
				pr("The "..p1.ship.shiptype.desc,63,20)
				pr(listofnames[p1.namesel],63,30,french)
			else
				pr(listofnames[p0.namesel],38,10,british)
				pr("vs.",63,20,7)
				pr(listofnames[p1.namesel],88,30,french)
			end
		end

		local function rf(a,b,c,d,k)
			rectfill(a+cx,b+cy,c+cx,d+cy,k)
		end

		-- display wind gauge
		local windinfo,winddir=" "..flr(wspeed).." kt ",dirarray[flr(min(0.99999,wangle+0.075)*#dirarray)+1]
		local winddirx=118-#winddir*5/2
		pr(windinfo,winddirx-#windinfo*6,120,7,align_left)
		pr(winddir,winddirx,120,7,align_left)
		rf(117,113,127,113,2)
		draw_voxel(windarrow,117+cx,113+cy,wangle+max(0.018,wspeed*0.002)*sin(t()/2))
		
		local function draw_player_hud(player,x)
			local ship=player.ship
			if ship then
				if ship.health > 0 then
					local dx=x+10
					rf(dx,2,dx+30*player.ship.health/player.ship.shiptype.health,4,player.ship.faction)
					rf(dx,7,dx+30*(player.charging and (1-min(120,player.chargetimer)/120) or (1-ship.reloadcounter/ship.shiptype.reloadtime)),7,player.charging and flr(rnd(14)+1) or 5)
				end
				spr(ship.health>0 and 64 or 80,x+cx,cy+1,5.25,1)
			end
		end

		draw_player_hud(p0,2)
		draw_player_hud(p1,83)
	end
end

function _draw()
	cls(killflash and 7 or timeofday)
	killflash=false

	if(timeofday==time_night) light(0.2)

	draw_display_list(particles[1])
	draw_display_list(nonwater_objects,true)

	light(1)
	draw_gamephase_hud()
end
__gfx__
eeeeeeeeeeeeeeeee4eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee4eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeee4eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee4eeeeee4eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000eeeeeeee07e
eeeeeeeeee4eeeeee4eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee2eeeeee4eeeeee4eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00070eeeeeee00e
eee2eeeee424eeee222eeee444eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee2e2eeee424eeee4e4eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000eeee55e5ee
ee222eee42224ee2eee2e7777777eeeeeee7777777e77777eeeeeeeee2eee2ee42224eee4e4eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000eeee5e5eee
e2eee2e42222244ee4ee4eee4eeeeee4eeeeee4eeeeee4eeeeee4eeee2eee2ee42224eeeeeeee7777777eeeeeee7777777e77777eee777eeee000eeee5eeeeee
e2eee2e42222244eeeee4eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0eee0ee42224eeeeeeeeeee4eeeeee4eeeeee4eeeeee4eeeeee4eeeeeeeeeeee07eeeee
e2eee2e02222204eeeee4eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee2eee2ee42224eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00eeeee
e2eee2e42222244eeeee47777777eeeeeee7777777e77777ee77777ee0eee0ee42224eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
e2eee2e02222204ee4ee4eee4eeeeee4eeeeee4eeeeee4eeeeee4eeee2eee2ee42224eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee06ee06eeee6eee
e2eee2e42222244eeeee4eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0eee0ee42224eeeeeeeeeeeeeee77777777777777e77777eeeeeeeee000e000eee00eee
e2eee2e02222204eeeee4e77777eeeeeeeee77777eee777eeeeeeeeee2eee2ee42224eeeeeeeeeee4eeeeee4eeeeee4eeeeee4eeeeee4eeeee0eee0eeee0eeee
e2eee2e42222244ee4ee4eee4eeeeee4eeeeee4eeeeee4eeeeeeeeeee0eee0ee42224eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee06eeeeaeeeee
e2eee2e0222220222222244444442222222eee7eeeeeeeeeeeeeeeeee2eee2ee42224ee42224eeee7eeeeee7eeeeee7eeeeeeeeeeeeeeeeeeee000eeeaeeeeee
e2eee2e4eeeee4222222244444442444442eee7eeeeee7eeeeeeeeeeee222eee42224ee42224eeee7eeeeee7eeeeee7eeeeeeeeeeeeeeeeeeeee0eee9a9eeeee
ee222eee24242e24a4a42424242422222226ee7ee6eee7eeeeeeeeeeeeeeeeeee4a4eee44444ee6e7e6eeee7eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeea99eeeee
eeeeeee4eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeaeeeeeeeeeeeeeeee2999999999999999999999999992ee
eeeeeee4ee7eeeeeeeeeeeeeeeeeeee4eeee7eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeaeeeeeeeeeeeeee22294444444444455444444444449222
eeee4ee4ee7ee7eeeeeeeeeeeeeeeee4eeee7eeee7eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeaeeeeeeeeeeeeee99944444444454455445444444444999
e4e4244e4e7ee7ee7eeeeeeeee2eeee2eeee7eeee7eeee7eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee9eeeeeeeeeeeeee94444444454444444444445444444449
e4e4244e4e7ee7ee7ee7eeeeee2eee424eee7eeee7eeee7eeee7eeeeeeeeeeeeeeeeeeeeeeeeeeeee9eeeeeeeeeeeeee94444544444444444444444444544449
e4e424eeee7ee7ee7ee7ee7eee2eee222eee7eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee9eeeeeeeeeeeeee94444454444444455444444445444449
e4e424e4ee4ee4ee4ee4eeeeee2eee020eeeeeeeeeee777777777777777eeeeeeeeeeeeeeeeeeeeee9eeeeeeeeeeeeee94444444444454444445444444444449
e4e424eeee7ee7eeeeeeeeeeee2eee242eee4eeee4eeee4eeee4eeee4eeeeeeeeeeeeeeeeeeeeeeee9eeeeeeeeeeeeee94444444444444444444444444444449
e4e424eeee7ee7ee7eeeeeeeee2eee020eeeeeeeeeeeee7eeee7eeee7eeeeeeeee5eeee5eeee0eeee9eeeeeeeeeeeeee94454444454444444444445444445449
e4e424eeee7ee7ee7ee7eeeeee2eee222eeeeeeeeeeeee7eeee7eeee7eeeeeeeeeeeeeeeeeeeeeeee9eeeeeeeeeeeeee94444444444444455444444444444449
e4e424eeee7ee7ee7ee7ee7eee2eee424ee424ee6e6eee7eeee7eeee7eeeeeeeeeeeeeeeeeee9eeee9eeee9eeeeeeeee94444444444444444444444444444449
e4e424e4ee4eeeeeeeeeeeeeeeeeee4a4ee444eeeeeeee7eeee7eeeeeeeeeeeeeeeeeeeeeeee9eeee9eeee9eeeeeeeee94444445444454444445444454444449
e4e4244e4e7ee7eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee9eee494eee9eeeeeeeee94544444444444444444444444444549
e4e444444e7ee7eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee9eee494eee9eeeeeeeee94444444444444455444444444444449
eee4a4444676e7ee7eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee9ee44944ee9eeeeeeeee94444444444444544544444444444449
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee9ee44944ee9eeeeeeeee95544544445445444454454444544559
eeee77eeeedddddddddddddddddddddddddddddddeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee95544544445445444454454444544559
eeeee7eeedeeeeeeeeeeeeeeeeeeeeeeee777eeeedeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee94444444444444544544444444444449
e22e74eeeeee7eeeeeeeeeeeeeeeeeeeeeee7eeeedeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee94444444444444455444444444444449
e4404044edeee77eeeeeeeeeeeeeeeeeeeeeeeeeedeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee94544444444444444444444444444549
ee22222eeedddddddddddddddddddddddddddddddeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee94444445444454444445444454444449
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee94444444444444444444444444444449
eee06eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee94444444444444455444444444444449
eee00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee94454444454444444444445444445449
eeee77eeeeddddddddddddddddeeeeddddddd7dddeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee94444444444444444444444444444449
eeeee7eeedeeeeeeeeeeeeeeedeeeddeeee77eeeedeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee94444444444454444445444444444449
e22e74eeeeee7eeeeeeeeeeeedeeeeddeeeeeeeeedeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee94444454444444455444444445444449
e4404044edeee77eeeeeeeeedeeedeeedeeeeeeeedeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee94444544444444444444444444544449
ee22222eeedddddddddddddddedeeeeedddddddddeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee94444444454444444444445444444449
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee99944444444454455445444444444999
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee22294444444444455444444444449222
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee2999999999999999999999999992ee
eeeeeedddeeeeeeeeeeeeeeeeeeeeeeeeeeeedddeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeedddeeeeeeeeeeedddddeeeeeeeeeeeeeeeeeeeeeeeeee
eeed777777deeed7777777ed7777deeeeeed777777e777777de777777deee7777777dd7777deeeeeee777777deeeedd777777777deeeeeeeeeeeeeeeeeeeeeee
eed77777777deed777777d0d77777deeeeed777777e777777de777777deed7777777dd777777eeeeee777777deeed777777777777deeeeeeeeeeeeeeeeeeeeee
ee77710e777deeeed77700eeed7777deeeeee777eeeed777deed777deeeeeee777eeeeee77777eeeeeed77d00ee77777d0000d7777eeeeeeeeeeeeeeeeeeeeee
ed77d0eed77deeeed77d0eeeed77777eeeeeed77eeeed777eee77deeeeeeeee777eeeeee77777deeeeee77deee7777d00eeeeee777eeeeeeeeeeeeeeeeeeeeee
ed77deeeed7deeeed77deeeeed777777eeeeed77eeeee77deed77eeeeeeeeee777eeeeee777777deeeee77deed77770eeeeeeeee77eeeeeeeeeeeeeeeeeeeeee
ed777eeeeee0eeeed77deeeeed777777deeeed77eeeee77dee77eeeeeeeeeee777eeeeee7777777eeeee77dee7777d0eeeeeeeeed70eeeeeeeeeeeeeeeeeeeee
ed7777deeeeeeeeed77deeeeed77ee777deeed77eeeee77de77deeeeeeeeeee777eeeeee77ded77deeee77ded77770eeeeeeeeeeee0eeeeeeeeeeeeeeeeeeeee
ee777777ddeeeeeed77deeeeed77eed777eeed77eeeee777777eeeeeeeeeeee777eeeeee77dee777deee77ded77770eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eee7777777deeeeed77deeeeed77eee7777eed77eeeee777777eeeeeeeeeeee777eeeeee77deed777dee77ded777d0eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeed777777deeeed77deeeeed77eeee777ded77eeeee777777deeeeeeeeeee777eeeeee77deeed777de77ded777deeeeeed777777eeeeeeeeeeeeeeeeeeeeee
eeeeeed77777eeeed77deeeeed77eeeed7777777eeeee7777777eeeeeeeeeee777eeeeee77deeee7777777dee777deeeeeed777777deeeeeeeeeeeeeeeeeeeee
eddeeeeed777eeeed77deeeeed77eeeeed777777eeeee77ded777eeeeeeeeee777eeeeee77deeeee777777dee777deeeeeeeed77770eeeeeeeeeeeeeeeeeeeee
e77deeeeed77deeed77deeeeed77eeeeee777777eeeee77deed77deeeeeeeee777eeeeee77deeeeed77777deed777eeeeeeeee777d0eeeeeeeeeeeeeeeeeeeee
e777eeeeed770eeed77deeeeed77eeeeeed77777eeeed77eeeed77deeeeeeee777eeeeee77deeeeeed7777deee7777eeeeeeee777deeeeeeeeeeeeeeeeeeeeee
e777deeee7770eeed777eeeeed77eeeeeeed7777eeeed77eeeeed77deeeeeee777deeeee77deeeeeee7777eeeee777deeeeeed777deeeeeeeeeeeeeeeeeeeeee
ed7777ded77d0eed7777deeed7777eeeeeee777deedd777deeeed7777deeed77777eeeed777deeeeeed7770eeeee7777ddeed7777deeeeeeeeeeeeeeeeeeeeee
eed7777777d0ed77777777dd777777deeeeed77dee777777deee7777777e77777777de777777deeeeeed770eeeeeed77777777777eeeeeeeeeeeeeeeeeeeeeee
eeedd7777d0eed777ddd77eed7777deeeeeeed7eeed77dddeeee77777dded77ddd77ded77777deeeeeeedd0eeeeeeeedd7777dde00eeeeeeeeeeeeeeeeeeeeee
eeeeee0000eeeee000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000eeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeedddeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeedddeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeed777777eee777777deeed7777777ee7777777ded777ddddddeeeeeeed777777eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeee777777777ed777777deeed777777ded7777777de77777777777deeee777777777eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeed77d00d777eee777deeeeeee7777eeeeee777eeeeed7777dd7777deed77d00d7770eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeee7770eeed77eeed77eeeeeeeed77deeeeee777eeeeeed77d0eed777ee7770eeed770eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeee7770eeee77eeed77eeeeeeeed77eeeeeee777eeeeeed77deeed777ee7770eeee770eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeee777deeeeeeeeed77eeeeeeeed77eeeeeee777eeeeeed77deeed777ee777deeeeee0eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeee7777ddeeeeeeed77deeeeeeed77eeeeeee777eeeeeed77deeed777ee7777ddeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeed777777deeeeed777deeeeed777eeeeeee777eeeeeed777eed7777eed777777deeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeed7777777deeed7777777777777eeeeeee777eeeeeed777777777eeeed7777777deeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeed777777eeed777ddddddd777eeeeeee777eeeeeed7777777deeeeeeed777777eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeed7777deed77eeeeeeeed77eeeeeee777eeeeeed777eeeeeeeeeeeeeed7777deeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeee7deeeee7777eed77eeeeeeeed77eeeeeee777eeeeeed77deeeeeeeee7deeeee7777eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeed77eeeeee7770ed77eeeeeeeed77eeeeeee777eeeeeed77deeeeeeeed77eeeeee7770eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeed77deeeee77d0ed77eeeeeeeed77eeeeeee777eeeeeed77deeeeeeeed77deeeee77d0eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeed777deeed77dee777deeeeeeed77deeeeee777deeeeed77deeeeeeeed777deeed77deeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeee7777ded777ee77777deeeeed7777deeed77777eeeed777deeeeeeeee7777ded7770eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeed77777777ee77777777eeed777777de77777777ded777777deeeeeeed7777777700eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeed7777deeed7dddddeeeeeddddddeed77ddd77ded77777deeeeeeeeeed7777d00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
ee77eeee77eee777eee777eeeeee7eee777eee77ee7777eeee777ee777eeee77eee777ee7777eeee777e7777ee7777ee77777eee777e77e77e7777eee7777eee
e7007eee07ee70007e70007eee770ee7000ee7007e0007eee7007e70007ee7007ee707ee07007ee7007e07007e07007e07007ee7007e07e07e0070eee0070eee
e7ee7eeee7ee0e770e0e777ee707eee777eee7ee0eee70eee7770e07777ee7ee7ee7e7eee7770ee7ee0ee7ee7ee77e0ee77e0e70ee0ee7777eee7eeeeee7eeee
70ee7eee70eee700eeee007e77777ee007ee7777eee70eee7007eee0007e70ee7e7777eee7007e70eeee70ee7ee70eeee70eee7ee77e77007ee70eeeee77eeee
7ee70eee7eee70ee7e7ee70e00070e7ee7ee7007ee77eeee7ee7ee7ee70e7ee70e7007ee70ee7e7eee7e7eee7e70ee7e70eeee7ee07e70e77ee7eeee7e70eeee
0777ee7777ee77770e0770eeee70ee0770ee7770ee70eeee7770ee0770ee0777ee7ee77e77770e77777e77770e77770e7eeeee07770e7ee70e777eee077eeeee
e000ee0000ee0000eee00eeeee0eeee00eee000eee0eeeee000eeee00eeee000ee0ee00e0000ee00000e0000ee0000ee0eeeeee000ee0ee0ee000eeee00eeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
77e77e777eee77e77e77e77ee777ee77777ee7777e7777eeee777e77777e77e77e77e77e77e77e77e77e77e77e77777eeeeeee77eeeeeeeeeeee77eeeeeeeeee
07e70e070eee07770e07e07ee7007e07007e70007e07007ee7007e00700e07e07e07e07e07e70e07e70e07e07e70007eeeeeee07eeeeeeeeeeee07eeeeeeeeee
e770eee7eeeee777eee77e7e70ee7ee7770e7eee7ee7e77ee77e0eee7eeee7ee7ee7ee7ee7e7eee070eee7770e0ee70ee77eeee777eee777eee777ee777eeeee
e707ee70eeeee707eee7077e7eee7ee700ee7eee7ee7700ee007eee70eee70ee7ee7ee7ee777eee707eee070eeee70ee7007ee7007ee7000ee7007ee707eeeee
77e7ee7eee7e77e7ee77e07e7ee77e70eeee07770e7707ee7ee07ee7eeee7eee7ee7770ee777eee7e7eee70eeee70e7e7e77ee7e70ee7eeeee7e77ee770e7eee
70e77e77770e70e77e70e77e77770e77eeeee0077e70e77e77770ee7eeee77770ee070ee77077e77e77e777eee77770e77007e077eee777eee7770ee07770eee
0ee00e0000ee0ee00e0ee00e0000ee00eeeeeee00e0ee00e0000eee0eeee0000eeee0eee00e00e00e00e000eee0000ee00ee0ee00eee000eee000eeee000eeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
ee77eeeeeeee77eeeeeeeeeeeeeeee77eeeee77eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee7eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
e700eeeeeeee07eeeeee7eeeeeeeee07e7eee07eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee7777eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
e7eeeee7777ee777eeee0eeeeeee7ee7e7eee70eeee7e7ee7777eee777eee777eee7777e77e7eeee777e0700eee7e7ee77e77e77e77e77e77e77e77e77777eee
7777ee70070ee707eee77eeeeeee7ee770eee7eeeee7777e07007e7007eee7007e70007e00707ee7000e70eeee70e7ee07e70e07e70e07770e07e70e00070eee
0700ee7ee7ee70e7eee70eeeeee70e7707eee7ee7e70707e77ee7e7ee7eee7ee7e7eee7ee70e0ee077ee7ee7ee7e77eee7e7eee777eee707eee7e7eee770eeee
e7eeee0770ee7e70ee70eeeeeee7ee70e7eee0770e7e0e7e70e77e7770eee7770e07770e77eeee7770ee7770ee0770eee770eee707ee70e07ee777ee77777eee
e0eeee7007ee0e0eee0eeeee7e70ee0ee0eeee00ee0eee0e0ee00e000eee7000eee007ee00eeee000eee000eeee00eeee00eeee0e0ee0eee0ee070ee00000eee
eeeeee7777eeeeeeeeeeeeee077eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee7eeeeeee77eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee77eeeeeeeeeee
eeeeee0000eeeeeeeeeeeeeee00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0eeeeeee00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00eeeeeeeeeee
eeeeeeeeeeeee777eeee77eee7e7eee77eeeee7eeeee7eeeeeeeeeeeeeeeee7eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeee0077eee77ee7070ee700eeee70eeeee07eee7eeeee7eeeee70eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeee77eee70ee0e0eee07e7eee7eeeeeee7eee0eeeee0eeeee0eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeee7770ee77eeeeeeeeee770eee7eeeeeee7eeeeeeeeeeeeeeeeeeee77777eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeee000eee00eeeeeeeee7007eee7eeeeeee7eee7eeeee7eeeeeeeeee00000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
ee7eee7eeeee7eeeeee7eeeeeeeeee07707ee07eeeee70ee70eeeee0eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
770eee0eeeee0eeeeee0eeeeeeeeeee00e0eee0eeeee0eee0eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000055100000000000000000000000000005510000000000000000000000000000000000000000000155000000000001555100000000000000000000000
00000016777775000567777770d666d5000000577777d0666667d06776775000d777777516666d0000000677777500001d77777777d100000000000000000000
00000577777777100d777777d0d77777500000577777606777775077777750016777776516777760000006777775000d77777667777750000000000000000000
00000776101777d0000d77600000d777750000007771000d777d0057765000000177710000077776000000d77d00006777650000567770000000000000000000
00005775000177d0000577500000577777000000d7600001776000d7d00000000067600000067777d000000775000d777d000000006771000000000000000000
0000d775000057500005775000005777776000005760000077500576000000000067600000067777750000067500577760000000000771000000000000000000
0000d776000001000005775000005776777d00005760000077500770000000000067600000067767770000067500677750000000000570000000000000000000
00005777650000000005775000005770177710005760000077d0675000000000006760000006750d77d000067501777700000000000000000000000000000000
00000677777d1000000d7750000057600d7760005760000077667600000000000077600000067500777500067505777600000000000000000000000000000000
0000006777777d00000d77d000005760006776005760000077777600000000000077700000067500577710067505777d00000000000000000000000000000000
00000005677777d0000d77d000005760000777d057600000777777500000000000777000000675000d7771077501777d00000057776660000000000000000000
0000000005677770000d77d000005760000577767760000077767770000000000077700000067500006777677500777d00000057777775000000000000000000
00005d00000d7771000577d0000057600000d7777760000077d0d776000000000067700000067500000777777500677d00000000d77760000000000000000000
000067500000d775000577d000005760000006777760000077500577d00000000067700000067500000577777500577710000000077750000000000000000000
0000777000005770000577d0000057700000017777600005770000177500000000677000000675000000d7777500067760000000077750000000000000000000
0000677d0000d760000d776000005770000000d77760000d7710000d77d000000077750000067d0000000777710000677d0000001777d0000000000000000000
0000d777610d775000d777750001d7760000000677d0015777d000057777500016777600005777500000057770000006776510016777d0000000000000000000
00000d77777775005777777761d77777710000017750067777750006777777067777777d0777777d000000d77000000056777777777610000000000000000000
0000005d77765000166655d6600d6666d000000016000166dd50000d6666d50d66d5d665056666650000000d50000000001d6666d51000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000155000000000000000000000000000000000000000000000000000001550000000000
000000000000000000000000000000000000000000000000000000000d77777d0006766665000d677666600d777777501d66ddddd50000000d77777d00000000
00000000000000000000000000000000000000000000000000000000677777776057777775000577777750167777765067777777777500006777777760000000
0000000000000000000000000000000000000000000000000000000d77500d777000677d0000001777610000177710000d7776556777100d77500d7770000000
00000000000000000000000000000000000000000000000000000007760000d7700057700000000d775000000676000000d775000d776007760000d770000000
00000000000000000000000000000000000000000000000000000007770000066000577000000005770000000676000000d77500057770077700000660000000
00000000000000000000000000000000000000000000000000000007775000001000577000000005770000000676000000d77500057770077750000010000000
00000000000000000000000000000000000000000000000000000006777d10000000577500000005770000000676000000d7750005777006777d100000000000
00000000000000000000000000000000000000000000000000000005777776500000577750000057770000000776000000d77600177760057777765000000000
00000000000000000000000000000000000000000000000000000000577777761000577777777777770000000777000000d77766777710005777777610000000
0000000000000000000000000000000000000000000000000000000000d7777770005776d5555557770000000777000000d7777666d1000000d7777770000000
000000000000000000000000000000000000000000000000000000000000d7777d0057710000000d770000000777000000d77600000000000000d7777d000000
00000000000000000000000000000000000000000000000000000006100001677600577000000005770000000677000000d77d00000000061000016776000000
00000000000000000000000000000000000000000000000000000057600000077600576000000005770000000677000000577500000000576000000776000000
000000000000000000000000000000000000000000000000000000d7750000067d00576000000005770000000677000000577500000000d7750000067d000000
00000000000000000000000000000000000000000000000000000057771000177500d77100000005775000000777500000577500000000577710001775000000
0000000000000000006000000000000000000000000000000000000777750167600d777750000057776100016777600005677d00000000077775016760000000
0000000000000000000000000000000d00000000000000000000000177777776006777777600057777775067777777d0d7777761000000017777777600000000
000000000000000000000000000000000000000000000000000000000d6777d00056d555510000dddddd00d66d5d6650566777d0000000000d6777d000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000060650000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000006565000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000d0000000066665000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000020055000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000650d000022006500000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000065650000022005500000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000066550000022065500000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000020050000022005500000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000020055000022066550000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000020055000022006550000202000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000020065500022066550200000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000020065500022006550200000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000065020065520022006550200000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000065556520066550002006655000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000082266555520066550000066655000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000082266555520066550000006550000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000082656555520066550000006550000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000020655555520066550000006655000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000022655555500006550000002655000000000000000000000000000000000000000000000000000000000000000000
00000505050000000100000000000000000002655555000006550002000000000000000000000000000000000000000000000000000000000000000000000000
00005050505000000000000000000000000002655000000006500200000000000000000000000000000000000000000000000000000000000000000000000000
00150505050500505050000000000000505052208200000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00505050505055050505000000001005050505282202000200020000000000000000000000000000000000000000000000000000000000000000000000000000
05050505050555505050550505000050515050582200002020000000000100000000000000000000000000000000000000000000000000000000000000000000
10105050505555050505555050500505050505252000000000000000111100000000000000000000000000000000000000000000000000000000000000000000
01010105055555505055555505055550505050525005050500000011111100000000000000000000000000000000000000000000000000000000000000000000
10101010505555555555555050505555050505050050505050501111111100000000000000000000000000000000000000000000000000000000000000000000
11010101055555555555555505055555505050505525050505151111111100000001000000000000000000000000000000000000000000000000000000000000
11101010105555555555555050505555550505055050505050515111111000000000000000000000000000000000000000000000000000000000000000000000
11110101015555555555555505055555555050555555550505051511110000000000000000000000000000000000000000000000000000000000000000000000
11101010101555555555555050505555550505055555555050505151100000000000000000000000000000000000000000000000000000000000000000000000
11110101010155555555550505050555555050555555555505050505000000000000000000000000000000000000000000000000000000000000000000000000
11111010101055555555505050505555550505055555555550505050000000000000000000000000000000000000000000000000000000000000000000000000
11110101010105555555050505055555555050555555555555050505000000000000000000000000000000000000000000000000000000000000000000000000
11111010101010505050505050505555550505055555555550505050500000000000000000000000000000000000000000000000000000000000000000000000
11110101010105050505050505055555555050505555555555050505050000000000000000000000000000000000000000000000000000000000000000000000
11101010101010505050005050505555550505050555555550505050500000000000000000000000000000000000000000000000000000000000000000000000
11110101010105050500050505050555555050505055555555050505050000000000000000000000000000000000000000000000000000000000000000000000
11101010101000505000005050505055550505050505055550505050500000000000000000000000000000000000000000000000000000000000000000000000
11010101010100000000000505050505505050505050555505050505050000000000000000000000000000000000000000000000000000000000000000000000
10101010101000000000000050505050050500050505055050505050500000000000000000000000000000000000000000000000000000000000000000000000
01010101010000000000000005050500000000005050500505050505000000000000000000000000000000000000000000000000000000000000000000000000
00001010000000000000000000505000000000000000000050505050000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000005050500000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000065000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000065202000655550000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000006655502000655550000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000006655552200555550000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000006565552000555550000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000006655652205555500000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000006565552655555002006555000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000c22655656555555020005555500000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000c222065556555550020005555500000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000c222000656555500022055555000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000002c20000006555500026555555000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000002000000655555000026555555500000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000200000655555000026555555500000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000022000665550000065555555000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000002000655500000065555555000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000002000065000000066555550000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000200000000000655505500000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000020000000000655555200000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000200000000655555200000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000002000000655550200000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000001000000100010000000200000655520020000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000002000655520000200000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000200655020000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000020650002000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000200000200020000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000002000020002000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000100000000000000000000000000000002002000020000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000d000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

__sfx__
000500000053003600066000a600051000f6000f6000e600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c00000075500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000200001a7101971018710127100f710087100671000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0004000037634326302e630286301b6300a630006350e600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010c0000137501375013750137501375513750137501375013755137551375013750137501375013750137501375013750137551370013700000000d700000000e70000000000000000000000000000000000000
001400000f700000000f7000f70014700000000000000000000000000000000000000000000000000000000000000000000000000000000000f750000000f7550f750147500f7000f70014700000000000000000
000800000100001000000000000000000000000000000000000000000000102031050200003000040002a1000500006000060000700008000080000800009000090000a0000a0000b0000b0000c0000011005110
0018000024636156361d63610636216361863623636136361c636286361a62215622106120c612096120461202612006120061200612006150060200602006020060200602006050060200602006050000000000
0018000024636106361a636266362063218622126220e6120b6120961205612036120161200612006120061503602026020160200602006020060200602006020060200602006050060200602006050000000000
0018000024636106361a636126320d6220d6220b61208612066120461202612006120061200615006020060503602026020160200602006020060200602006020060200602006050060200602006050000000000
0018000024636176320c6220961206612046120261202612016150160200605036020260201602006020060200602006020060200602006020060500602006020060500000000000000000000000000000000000
000b0000007741e627036200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000700000a774167731977318770137700f7700677003760027500175000740007300072000720007100071000715045000350003500005000060000600006000060000600006000060000600005000050000505
011000000e7000e7000e7000e7000e7000e7000e7000e7000e7000e7000e7000e7000e7000e7000e7000e7000e7520e7520e7520e7520e7520e7550e7000e7520e7520e7520e7520e7550e7520e7550e7520e752
011000000e7520e7520e7520e755117521175211752117521175510752107551075210752107521075210752107550e7520e7550e7520e7520e7520e7520e7550d7520d7550e7520e7520e7520e7520e7520e752
011000000e7520e7520e7520e75502700027001c7001c7001c7001c70000700007002170021700217002170005700057001f7001f7001f7001f70000700097002270022700227002270007700077002170021700
010700000e7000e700027000270000700007000970009700097001570000700007001170011700117001170000700007000c7000c7000c7001870000700007000770007700137001370000700007000e7000e700
011400000e7510e7500e7500e7500e755137501375013750137501375513750137501375013755137551375213752137521375213755177501775017750177551575513750137501375013755127551375013750
011400001375013755107550e7520e7520e7520e7520e7520e7550e7001550015500155001550019700197000e5000e5000e5000e50002700135000d5000d5000d5000d500097000970011500115001150011500
0105000021700217000e7000e7000a7000a700167001670000700007002570025700257002570015700157001d7001d7001d7001d70002700027001c7001c7001c7001c700097001570021700217002170021700
010500000e7000e70000700007000070000700007000070000700007001570015700097000970000700007000e7000e7000270002700007000070009700097000970015700007000070011700117001170011700
01140000007001f500185001850000700007750d7001e5001a5000070000775007000070000700007450077518500215002650025500265002850029500295000074500775007001d5001d5001d5000050000500
01140000007000070000745007751c5001c50018700215001f7001f700185001850022700105001d5001d5001d5000e5001650016500135001350015500155000950009500215002150021500215000270002700
0110000000700007000c7000c7000c7001870000700097001f7001f7001f7001f7002270022700217002170000775007000070000700007000070000700007750070000700267000070000745007000077502700
0110000000700007000c7000c7000c700187000070000700227000074500700007750070000700117001170000700007450070000775007000070000700007000074500700007750070000700007000070000700
0110000000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007001c500175001850021500135001a5001f500265002450022500215001f500
000500001d0300c020010200d02019020060301803011020070200202000020072000520003200022000220001200012000020001200002000020000200012000120000200002001650013500135001a5001a500
000d00000e610066000f6001b60528600056000360002600016000160500700007000070011700217001d7000070000700007001f700007000070000700187000070013700227001f70000700007000070021700
012d00001d5001c5001a5001850016500215001f500295002850026500255002850021500255001c5001f5000e500155001a500215001f5001d5001c5001a5001950013500155001050011500185001d50024500
012d00000e5000e500005002150026500265000a5000a50016500165001550015500155001350011500105001d5001d50011500115000e5000e50015500155000950009500005000050021500215001550015500
012d0000005000050000500007002170016700267001f7000070000700007000070000700007000070000700007000e7001d7001a7000070000700007001c700007001970000700007000070011700217001d700
012d000022500215001f5001a5001c500165001850021500135001a5001f5002650024500225001a5001f5001d50021500165001d50026500285002150026500255001f5002650022500215001f5001d5001c500
012d0000115001150018500185000c5000c50000500125002250022500165001650013500135002150021500215001c50026500155001f50022500295002950028500285000e5000e5000e5000e5000250002500
012d00000070000700007001f700007001c70000700187000070013700227001f7000070000700007001a70000700187000070026700167001370015700157000970009700007002670026700267000070000700
012d00000e5000d5000e500105001150013500155001350015500105000d50009500115001050011500135001550016500185001350010500135000c500105001350011500135001550016500185001a50015500
012d00001550015500155001550015500155001950019500195001950019500195001850018500185001850018500185001c5001c5001c5001c5001c5001c5001a5001a5001f5001f5001f5001f5001d5001d500
012d00001a7001a7001a7001a7001a7001a7001c7001c7001c7001c7001c7001c7002170021700217002170021700217001f7001f7001f7001f7001f7001f7002270022700227002270022700227002170021700
012d00001d7001d7001d7001d7001d7001d7000050000500005000050000500005000050000500005000050000500000000000000000000000000000000000000000000000000000000000000005000050000500
012d000011500155000e500115000a50011500165001550013500265001550016500155001350011500105000e5000950005500095000250005500095001050015500135001150010500115000c500095000c500
012d00001d5001d5001d5001d5002650026500285002850028500165001c5001c5001c5001c5001c5001c5001550015500155001550015500155001950019500195001950019500195001d5001d5001d5001d500
012d00002170021700217002170021700217001f7001f7001f7001f7002170021700217002170021700217001a7001a7001a7001a7001a7001a7001c7001c7001c7001c7001c7001c70021700217002170021700
012d0000000000000000000000000050000500005000050000700007002570025700257002570025700257001d7001d7001d7001d7001d7001d70000700007000050000000000000000000000000000000000000
002d000005500095000c5000a5000c5000e5001050011500135000e5000a5000e500075000a5000e500105000e5002150026500255002650028500215002650025500215001a5001550011500155000e5000e500
012d00001d5001d5001c5001c5001c5001c5001c5001c5001a5001a5001f5001f5001f5001f5002150021500215000c5000a500095000a50007500155001350015500095001d5001d5001d5001d5000050000500
012d000021700217001f7001f7001f7001f7001f7001f7002270022700227002270022700227001d7001d7001d7001d7001f7001f700007000070029700297002870028700217002170021700217000070000500
012d00000050000500005000050000000000000000000500005000050000500005000050000500005000050000500005000050000500005000050000500005000070000700267002670026700267000050000500
__music__
01 10424344
01 0d174344
01 0e184344
04 0f594344
01 13424344
01 11154344
04 12164344
01 13424344
04 04424344

