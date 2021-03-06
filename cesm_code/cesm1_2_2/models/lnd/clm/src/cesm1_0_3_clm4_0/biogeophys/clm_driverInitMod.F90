
module clm_driverInitMod

!-----------------------------------------------------------------------
!BOP
!
! !MODULE: clm_driverInitMod
!
! !DESCRIPTION:
! Initialization of clm driver variables needed from previous timestep
!! USE
  use clm_varctl, only : iulog
!
! !PUBLIC TYPES:
  implicit none
  save
!
! !PUBLIC MEMBER FUNCTIONS:
  public :: clm_driverInit
!
! !REVISION HISTORY:
! Created by Mariana Vertenstein
! 10/29/2012 Jing Chen : Initialization of EASS driver variables fom previous timestep
!
!EOP
!-----------------------------------------------------------------------

contains

!-----------------------------------------------------------------------
!BOP
!
! !IROUTINE: clm_driverInit
!
! !INTERFACE:
  subroutine clm_driverInit(lbc, ubc, lbp, ubp, &
             num_nolakec, filter_nolakec, num_lakec, filter_lakec)
!
! !DESCRIPTION:
! Initialization of clm driver variables needed from previous timestep
!
! !USES:
    use shr_kind_mod , only : r8 => shr_kind_r8
    use clmtype
    use clm_varpar   , only : nlevsno
    use subgridAveMod, only : p2c
    use clm_varcon   , only : h2osno_max, rair, cpair, grav, istice_mec, lapse_glcmec
    use clm_atmlnd   , only : clm_a2l
    use domainMod    , only : ldomain
    use clmtype
    use QsatMod      , only : Qsat

!
! !ARGUMENTS:
    implicit none
    integer, intent(in) :: lbc, ubc                    ! column-index bounds
    integer, intent(in) :: lbp, ubp                    ! pft-index bounds
    integer, intent(in) :: num_nolakec                 ! number of column non-lake points in column filter
    integer, intent(in) :: filter_nolakec(ubc-lbc+1)   ! column filter for non-lake points
    integer, intent(in) :: num_lakec                   ! number of column non-lake points in column filter
    integer, intent(in) :: filter_lakec(ubc-lbc+1)     ! column filter for non-lake points
!
! !CALLED FROM:
! subroutine driver1
!
! !REVISION HISTORY:
! Created by Mariana Vertenstein
!
!
! !LOCAL VARIABLES:
!
! local pointers to original implicit in variables
!
    real(r8), pointer :: pwtgcell(:)           ! weight of pft wrt corresponding gridcell
    integer , pointer :: snl(:)                ! number of snow layers
    real(r8), pointer :: h2osno(:)             ! snow water (mm H2O)
    integer , pointer :: frac_veg_nosno_alb(:) ! fraction of vegetation not covered by snow (0 OR 1) [-]
    integer , pointer :: frac_veg_nosno(:)     ! fraction of vegetation not covered by snow (0 OR 1 now) [-] (pft-level)
    real(r8), pointer :: h2osoi_ice(:,:)       ! ice lens (kg/m2)
    real(r8), pointer :: h2osoi_liq(:,:)       ! liquid water (kg/m2)
    !----------------
    ! added by Jing Chen, Oct 19 2012
    integer , pointer :: snl_EASS(:)                ! number of snow layers
    real(r8), pointer :: h2osoi_ice_EASS(:,:)       ! ice lens (kg/m2)
    real(r8), pointer :: h2osoi_liq_EASS(:,:)       ! liquid water (kg/m2)
    !----------------
!
! local pointers to original implicit out variables
!
    logical , pointer :: do_capsnow(:)         ! true => do snow capping
    real(r8), pointer :: h2osno_old(:)         ! snow water (mm H2O) at previous time step
    real(r8), pointer :: frac_iceold(:,:)      ! fraction of ice relative to the tot water
    !-------------------
    ! added by Jing Chen Oct 19 2012
    real(r8), pointer :: frac_iceold_EASS(:,:) ! fraction of ice relative to the tot water
    real(r8), pointer :: densnow_EASS(:)       ! snow denisity on the ground [kg m-3]
    real(r8), pointer :: ponddp_EASS(:)        ! water pond depth[m]
    !-------------------
!
! !OTHER LOCAL VARIABLES:
!EOP
!
    integer :: g, l, c, p, f, j, fc            ! indices

    real(r8), pointer :: qflx_glcice(:)     ! flux of new glacier ice (mm H2O/s) [+ = ice grows]
    real(r8), pointer :: eflx_bot(:)        ! heat flux from beneath soil/ice column (W/m**2)
    real(r8), pointer :: glc_topo(:)        ! sfc elevation for glacier_mec column (m)
    real(r8), pointer :: forc_t(:)          ! atmospheric temperature (Kelvin)
    real(r8), pointer :: forc_th(:)         ! atmospheric potential temperature (Kelvin)
    real(r8), pointer :: forc_q(:)          ! atmospheric specific humidity (kg/kg)
    real(r8), pointer :: forc_pbot(:)       ! atmospheric pressure (Pa)
    real(r8), pointer :: forc_rho(:)        ! atmospheric density (kg/m**3)
    integer , pointer :: cgridcell(:)       ! column's gridcell
    integer , pointer :: clandunit(:)       ! column's landunit
    integer , pointer :: plandunit(:)       ! pft's landunit
    integer , pointer :: ityplun(:)         ! landunit type
    !-------------------------
    ! added by Jing Chen Oct 19 2012
    real(r8), pointer :: eflx_bot_EASS(:)    ! heat flux from beneath soil/ice column (W/m**2)
    real(r8), pointer :: qflx_glcice_EASS(:) ! flux of new glacier ice (mm H2O/s) [+ = ice grows]
    !------------------------

    ! temporaries for topo downscaling
    real(r8) :: hsurf_g,hsurf_c,Hbot
    real(r8) :: zbot_g, tbot_g, pbot_g, thbot_g, qbot_g, qs_g, es_g
    real(r8) :: zbot_c, tbot_c, pbot_c, thbot_c, qbot_c, qs_c, es_c
    real(r8) :: egcm_c, rhos_c
    real(r8) :: dum1,   dum2

!-----------------------------------------------------------------------

    ! Assign local pointers to derived type members (landunit-level)

    ityplun            => clm3%g%l%itype

    ! Assign local pointers to derived type members (column-level)

    snl                => clm3%g%l%c%cps%snl
    h2osno             => clm3%g%l%c%cws%h2osno
    h2osno_old         => clm3%g%l%c%cws%h2osno_old
    do_capsnow         => clm3%g%l%c%cps%do_capsnow
    frac_iceold        => clm3%g%l%c%cps%frac_iceold
    h2osoi_ice         => clm3%g%l%c%cws%h2osoi_ice
    h2osoi_liq         => clm3%g%l%c%cws%h2osoi_liq
    frac_veg_nosno_alb => clm3%g%l%c%p%pps%frac_veg_nosno_alb
    frac_veg_nosno     => clm3%g%l%c%p%pps%frac_veg_nosno
    qflx_glcice        => clm3%g%l%c%cwf%qflx_glcice
    eflx_bot           => clm3%g%l%c%cef%eflx_bot
    glc_topo           => clm3%g%l%c%cps%glc_topo
    forc_t             => clm3%g%l%c%ces%forc_t
    forc_th            => clm3%g%l%c%ces%forc_th
    forc_q             => clm3%g%l%c%cws%forc_q
    forc_pbot          => clm3%g%l%c%cps%forc_pbot
    forc_rho           => clm3%g%l%c%cps%forc_rho
    clandunit          => clm3%g%l%c%landunit
    cgridcell          => clm3%g%l%c%gridcell
    !-----------------
    ! added by Jing Chen Oct 19 2012
    eflx_bot_EASS      => clm3%g%l%c%cef%eflx_bot_EASS
    qflx_glcice_EASS   => clm3%g%l%c%cwf%qflx_glcice_EASS
    frac_iceold_EASS   => clm3%g%l%c%cps%frac_iceold_EASS
    h2osoi_ice_EASS    => clm3%g%l%c%cws%h2osoi_ice_EASS
    h2osoi_liq_EASS    => clm3%g%l%c%cws%h2osoi_liq_EASS
    snl_EASS           => clm3%g%l%c%cps%snl_EASS
    densnow_EASS       => clm3%g%l%c%cwf%densnow_EASS
    ponddp_EASS        => clm3%g%l%c%cps%ponddp_EASS
    !------------------

    ! Assign local pointers to derived type members (pft-level)

    pwtgcell           => clm3%g%l%c%p%wtgcell
    plandunit          => clm3%g%l%c%p%landunit
!-------------------------------------------------------

   do c = lbc, ubc

      g = cgridcell(c)

      ! Initialize column forcing

      forc_t(c)    = clm_a2l%forc_t(g)
      forc_th(c)   = clm_a2l%forc_th(g)
      forc_q(c)    = clm_a2l%forc_q(g)
      forc_pbot(c) = clm_a2l%forc_pbot(g)
      forc_rho(c)  = clm_a2l%forc_rho(g)

      ! Save snow mass at previous time step
      h2osno_old(c) = h2osno(c)

      ! Decide whether to cap snow
      if (h2osno(c) > h2osno_max) then
         do_capsnow(c) = .true.
      else
         do_capsnow(c) = .false.
      end if
      eflx_bot(c)    = 0._r8
      qflx_glcice(c) = 0._r8
      !------------------
      ! added by Jing Chen Oct 19 2012
      eflx_bot_EASS(c)    = 0._r8
      qflx_glcice_EASS(c) = 0._r8
      densnow_EASS(c) = 100.0_r8 * 2.0_r8    ![kg m-3]
      ponddp_EASS(c)  = 0.0_r8
      !-------------------
    end do

    ! Initialize fraction of vegetation not covered by snow (pft-level)

    do p = lbp,ubp
       l = plandunit(p)
       ! Note: Some glacier_mec points may have zero weight
       if (pwtgcell(p)>0._r8 .or. ityplun(l) == istice_mec) then
          frac_veg_nosno(p) = frac_veg_nosno_alb(p)
       else
          frac_veg_nosno(p) = 0._r8
       end if
    end do

    ! Initialize set of previous time-step variables
    ! Ice fraction of snow at previous time step
    ! used in SnowCompaction_EASS
    do j = -nlevsno+1,0
      do f = 1, num_nolakec
         c = filter_nolakec(f)
         if (j >= snl(c) + 1) then
             frac_iceold(c,j) = h2osoi_ice(c,j)/(h2osoi_liq(c,j)+h2osoi_ice(c,j))
         end if
         !-------------------
         ! added by Jing Chen Oct 19 2012
         if (j >= snl_EASS(c) + 1) then
             frac_iceold_EASS(c,j) = h2osoi_ice_EASS(c,j)/(h2osoi_liq_EASS(c,j)+h2osoi_ice_EASS(c,j))
         end if
         !------------------
      end do
    end do

   ! Downscale forc_t, forc_th, forc_q, forc_pbot, and forc_rho to columns.
   ! For glacier_mec columns the downscaling is based on surface elevation.
   ! For other columns the downscaling is a simple copy.

    do f = 1, num_nolakec
       c = filter_nolakec(f)
       l = clandunit(c)
       g = cgridcell(c)

       if (ityplun(l) == istice_mec) then   ! downscale to elevation classes

          ! This is a simple downscaling procedure taken from subroutine clm_mapa2l.
          ! Note that forc_hgt, forc_u, and forc_v are not downscaled.

          hsurf_g = ldomain%topo(g)          ! gridcell sfc elevation
          hsurf_c = glc_topo(c)              ! column sfc elevation

          tbot_g  = clm_a2l%forc_t(g)        ! atm sfc temp
          thbot_g = clm_a2l%forc_th(g)       ! atm sfc pot temp
          qbot_g  = clm_a2l%forc_q(g)        ! atm sfc spec humid
          pbot_g  = clm_a2l%forc_pbot(g)     ! atm sfc pressure
          zbot_g  = clm_a2l%forc_hgt(g)      ! atm ref height

          zbot_c  = zbot_g
          tbot_c  = tbot_g-lapse_glcmec*(hsurf_c-hsurf_g)   ! sfc temp for column

          Hbot    = rair*0.5_r8*(tbot_g+tbot_c)/grav        ! scale ht at avg temp
          pbot_c  = pbot_g*exp(-(hsurf_c-hsurf_g)/Hbot)     ! column sfc press
          thbot_c = tbot_c*exp((zbot_c/Hbot)*(rair/cpair))  ! pot temp calc

          call Qsat(tbot_g,pbot_g,es_g,dum1,qs_g,dum2)
          call Qsat(tbot_c,pbot_c,es_c,dum1,qs_c,dum2)

          qbot_c  = qbot_g*(qs_c/qs_g)
          egcm_c  = qbot_c*pbot_c/(0.622+0.378*qbot_c)
          rhos_c  = (pbot_c-0.378*egcm_c) / (rair*tbot_c)

          forc_t(c)    = tbot_c
          forc_th(c)   = thbot_c
          forc_q(c)    = qbot_c
          forc_pbot(c) = pbot_c
          forc_rho(c)  = rhos_c

       endif

    enddo    ! num_nolakec

  end subroutine clm_driverInit

end module clm_driverInitMod
