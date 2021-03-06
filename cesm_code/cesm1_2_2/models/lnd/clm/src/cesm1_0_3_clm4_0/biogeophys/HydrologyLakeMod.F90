module HydrologyLakeMod

!-----------------------------------------------------------------------
!BOP
!
! !MODULE: HydrologyLakeMod
!
! !DESCRIPTION:
! Calculate lake hydrology
!
! !PUBLIC TYPES:
  implicit none
  save
!
! !PUBLIC MEMBER FUNCTIONS:
  public :: HydrologyLake
!
! !REVISION HISTORY:
! Created by Mariana Vertenstein
!
!EOP
!-----------------------------------------------------------------------

contains

!-----------------------------------------------------------------------
!BOP
!
! !IROUTINE: HydrologyLake
!
! !INTERFACE:
  subroutine HydrologyLake(lbp, ubp, num_lakep, filter_lakep)
!
! !DESCRIPTION:
! Calculate lake hydrology
!
! WARNING: This subroutine assumes lake columns have one and only one pft.
!
! !USES:
    use shr_kind_mod, only: r8 => shr_kind_r8
    use clmtype
    use clm_atmlnd  , only : clm_a2l
    use clm_time_manager, only : get_step_size
    use clm_varcon  , only : hfus, tfrz, spval
    use clm_varctl  , only : iulog
!
! !ARGUMENTS:
    implicit none
    integer, intent(in) :: lbp, ubp                ! pft-index bounds
    integer, intent(in) :: num_lakep               ! number of pft non-lake points in pft filter
    integer, intent(in) :: filter_lakep(ubp-lbp+1) ! pft filter for non-lake points
!
! !CALLED FROM:
! subroutine clm_driver1
!
! !REVISION HISTORY:
! Author: Gordon Bonan
! 15 September 1999: Yongjiu Dai; Initial code
! 15 December 1999:  Paul Houser and Jon Radakovich; F90 Revision
! 3/4/02: Peter Thornton; Migrated to new data structures.
!
! !LOCAL VARIABLES:
!
! local pointers to implicit in arrays
!
    integer , pointer :: pcolumn(:)         !pft's column index
    integer , pointer :: pgridcell(:)       !pft's gridcell index
    real(r8), pointer :: begwb(:)         !water mass begining of the time step
    real(r8), pointer :: forc_snow(:)     !snow rate [mm/s]
    real(r8), pointer :: forc_rain(:)     !rain rate [mm/s]
    logical , pointer :: do_capsnow(:)    !true => do snow capping
    real(r8), pointer :: t_grnd(:)        !ground temperature (Kelvin)
    real(r8), pointer :: qmelt(:)         !snow melt [mm/s]
    real(r8), pointer :: qflx_evap_soi(:) !soil evaporation (mm H2O/s) (+ = to atm)
    real(r8), pointer :: qflx_evap_tot(:) !qflx_evap_soi + qflx_evap_can + qflx_tran_veg
!
! local pointers to implicit inout arrays
!
    real(r8), pointer :: h2osno(:)        !snow water (mm H2O)
!
! local pointers to implicit out arrays
!
    real(r8), pointer :: endwb(:)         !water mass end of the time step
    real(r8), pointer :: snowdp(:)        !snow height (m)
    real(r8), pointer :: snowice(:)       !average snow ice lens
    real(r8), pointer :: snowliq(:)       !average snow liquid water
    real(r8), pointer :: eflx_snomelt(:)  !snow melt heat flux (W/m**2)
    real(r8), pointer :: qflx_infl(:)     !infiltration (mm H2O /s)
    real(r8), pointer :: qflx_snomelt(:)  !snow melt (mm H2O /s)
    real(r8), pointer :: qflx_surf(:)     !surface runoff (mm H2O /s)
    real(r8), pointer :: qflx_drain(:)    !sub-surface runoff (mm H2O /s)
    real(r8), pointer :: qflx_irrig(:)    !irrigation flux (mm H2O /s)
    real(r8), pointer :: qflx_qrgwl(:)    !qflx_surf at glaciers, wetlands, lakes
    real(r8), pointer :: qflx_runoff(:)   !total runoff (qflx_drain+qflx_surf+qflx_qrgwl) (mm H2O /s)
    real(r8), pointer :: qflx_snwcp_ice(:)!excess snowfall due to snow capping (mm H2O /s) [+]
    real(r8), pointer :: qflx_evap_tot_col(:) !pft quantity averaged to the column (assuming one pft)
    real(r8) ,pointer :: soilalpha(:)     !factor that reduces ground saturated specific humidity (-)
    real(r8), pointer :: zwt(:)           !water table depth
    real(r8), pointer :: fcov(:)          !fractional impermeable area
    real(r8), pointer :: fsat(:)          !fractional area with water table at surface
    real(r8), pointer :: qcharge(:)       !aquifer recharge rate (mm/s)
    !---------------------
    ! added by Jing Chen Oct 22 2012
    real(r8), pointer :: h2osno_EASS(:)        !snow water (mm H2O)
    real(r8), pointer :: endwb_EASS(:)         !water mass end of the time step
    real(r8), pointer :: snowdp_EASS(:)        !snow height (m)
    real(r8), pointer :: snowice_EASS(:)       !average snow ice lens
    real(r8), pointer :: snowliq_EASS(:)       !average snow liquid water
    real(r8), pointer :: eflx_snomelt_EASS(:)  !snow melt heat flux (W/m2)
    real(r8), pointer :: qflx_infl_EASS(:)     !infiltration (mm H2O /s)
    real(r8), pointer :: qflx_snomelt_EASS(:)  !snow melt (mm H2O /s)
    real(r8), pointer :: qflx_surf_EASS(:)     !surface runoff (mm H2O /s)
    real(r8), pointer :: qflx_drain_EASS(:)    !sub-surface runoff (mm H2O /s)
    real(r8), pointer :: qflx_snwcp_ice_EASS(:)!excess snowfall due to snow capping (mm H2O /s) [+]
    real(r8), pointer :: qflx_qrgwl_EASS(:)    !qflx_surf at glaciers, wetlands, lakes
    real(r8), pointer :: qflx_runoff_EASS(:)   !total runoff (qflx_drain+qflx_surf+qflx_qrgwl) (mm H2O /s)
    real(r8), pointer :: zwt_EASS(:)           !water table depth
    real(r8), pointer :: qcharge_EASS(:)       !aquifer recharge rate (mm/s)
    !--------------------------
!
! local pointers to implicit out multi-level arrays
!
    real(r8), pointer :: rootr_column(:,:) !effective fraction of roots in each soil layer
    real(r8), pointer :: h2osoi_vol(:,:)   !volumetric soil water (0<=h2osoi_vol<=watsat) [m3/m3]
    real(r8), pointer :: h2osoi_ice(:,:)   !ice lens (kg/m2)
    real(r8), pointer :: h2osoi_liq(:,:)   !liquid water (kg/m2)
    !-------------------
    ! added by Jing Chen Oct 22 2012
    real(r8), pointer :: rootr_column_EASS(:,:) !effective fraction of roots in each soil layer
    real(r8), pointer :: h2osoi_vol_EASS(:,:)   !volumetric soil water (0<=h2osoi_vol<=watsat) [m3/m3]
    real(r8), pointer :: h2osoi_ice_EASS(:,:)   !ice lens (kg/m2)
    real(r8), pointer :: h2osoi_liq_EASS(:,:)   !liquid water (kg/m2)
    !-----------------
!
!
! !OTHER LOCAL VARIABLES:
!EOP
    real(r8), parameter :: snow_bd = 250._r8  !constant snow bulk density
    integer  :: fp, p, c, g    ! indices
    real(r8) :: dtime          ! land model time step (sec)
    real(r8) :: qflx_evap_grnd ! ground surface evaporation rate (mm h2o/s)
    real(r8) :: qflx_dew_grnd  ! ground surface dew formation (mm h2o /s) [+]
    real(r8) :: qflx_sub_snow  ! sublimation rate from snow pack (mm h2o /s) [+]
    real(r8) :: qflx_dew_snow  ! surface dew added to snow pack (mm h2o /s) [+]
!-----------------------------------------------------------------------

    ! Assign local pointers to derived type gridcell members

    forc_snow    => clm_a2l%forc_snow
    forc_rain    => clm_a2l%forc_rain

    ! Assign local pointers to derived type column members

    begwb          => clm3%g%l%c%cwbal%begwb
    endwb          => clm3%g%l%c%cwbal%endwb
    do_capsnow     => clm3%g%l%c%cps%do_capsnow
    snowdp         => clm3%g%l%c%cps%snowdp
    t_grnd         => clm3%g%l%c%ces%t_grnd
    h2osno         => clm3%g%l%c%cws%h2osno
    snowice        => clm3%g%l%c%cws%snowice
    snowliq        => clm3%g%l%c%cws%snowliq
    eflx_snomelt   => clm3%g%l%c%cef%eflx_snomelt
    qmelt          => clm3%g%l%c%cwf%qmelt
    qflx_snomelt   => clm3%g%l%c%cwf%qflx_snomelt
    qflx_surf      => clm3%g%l%c%cwf%qflx_surf
    qflx_qrgwl     => clm3%g%l%c%cwf%qflx_qrgwl
    qflx_runoff    => clm3%g%l%c%cwf%qflx_runoff
    qflx_snwcp_ice => clm3%g%l%c%cwf%pwf_a%qflx_snwcp_ice
    qflx_drain     => clm3%g%l%c%cwf%qflx_drain
    qflx_irrig     => clm3%g%l%c%cwf%qflx_irrig
    qflx_infl      => clm3%g%l%c%cwf%qflx_infl
    rootr_column   => clm3%g%l%c%cps%rootr_column
    h2osoi_vol     => clm3%g%l%c%cws%h2osoi_vol
    h2osoi_ice     => clm3%g%l%c%cws%h2osoi_ice
    h2osoi_liq     => clm3%g%l%c%cws%h2osoi_liq
    qflx_evap_tot_col => clm3%g%l%c%cwf%pwf_a%qflx_evap_tot
    soilalpha      => clm3%g%l%c%cws%soilalpha
    zwt            => clm3%g%l%c%cws%zwt
    fcov           => clm3%g%l%c%cws%fcov
    fsat           => clm3%g%l%c%cws%fsat
    qcharge        => clm3%g%l%c%cws%qcharge
    !------------------
    ! added by Jing Chen Oct 22 2012
    h2osno_EASS         => clm3%g%l%c%cws%h2osno_EASS
    endwb_EASS          => clm3%g%l%c%cwbal%endwb_EASS
    snowdp_EASS         => clm3%g%l%c%cps%snowdp_EASS
    snowice_EASS        => clm3%g%l%c%cws%snowice_EASS
    snowliq_EASS        => clm3%g%l%c%cws%snowliq_EASS
    eflx_snomelt_EASS   => clm3%g%l%c%cef%eflx_snomelt_EASS
    qflx_snomelt_EASS   => clm3%g%l%c%cwf%qflx_snomelt_EASS
    qflx_surf_EASS      => clm3%g%l%c%cwf%qflx_surf_EASS
    qflx_qrgwl_EASS     => clm3%g%l%c%cwf%qflx_qrgwl_EASS
    qflx_runoff_EASS    => clm3%g%l%c%cwf%qflx_runoff_EASS
    qflx_snwcp_ice_EASS => clm3%g%l%c%cwf%pwf_a%qflx_snwcp_ice_EASS
    qflx_drain_EASS     => clm3%g%l%c%cwf%qflx_drain_EASS
    qflx_infl_EASS      => clm3%g%l%c%cwf%qflx_infl_EASS
    rootr_column_EASS   => clm3%g%l%c%cps%rootr_column_EASS
    h2osoi_vol_EASS     => clm3%g%l%c%cws%h2osoi_vol_EASS
    h2osoi_ice_EASS     => clm3%g%l%c%cws%h2osoi_ice_EASS
    h2osoi_liq_EASS     => clm3%g%l%c%cws%h2osoi_liq_EASS
    zwt_EASS            => clm3%g%l%c%cws%zwt_EASS
    qcharge_EASS        => clm3%g%l%c%cws%qcharge_EASS
    !------------------

    ! Assign local pointers to derived type pft members

    pcolumn       => clm3%g%l%c%p%column
    pgridcell     => clm3%g%l%c%p%gridcell
    qflx_evap_soi => clm3%g%l%c%p%pwf%qflx_evap_soi
    qflx_evap_tot => clm3%g%l%c%p%pwf%qflx_evap_tot

!----------------------------------------------------
    ! Determine step size

    dtime = get_step_size()

    do fp = 1, num_lakep
       p = filter_lakep(fp)
       c = pcolumn(p)
       g = pgridcell(p)

       ! Snow on the lake ice
       ! Note that these are only local variables, as per the original
       ! Hydrology_Lake code. So even though these names correspond to
       ! variables in clmtype, this routine is not updating the
       ! values of the clmtype variables. (PET, 3/4/02)

       qflx_evap_grnd = 0._r8
       qflx_sub_snow  = 0._r8
       qflx_dew_snow  = 0._r8
       qflx_dew_grnd  = 0._r8

       if (qflx_evap_soi(p) >= 0._r8) then

          ! Sublimation: do not allow for more sublimation than there is snow
          ! after melt.  Remaining surface evaporation used for infiltration.

          qflx_sub_snow = min(qflx_evap_soi(p), h2osno(c)/dtime-qmelt(c))
          qflx_evap_grnd = qflx_evap_soi(p) - qflx_sub_snow

       else

          if (t_grnd(c) < tfrz-0.1_r8) then
             qflx_dew_snow = abs(qflx_evap_soi(p))
          else
             qflx_dew_grnd = abs(qflx_evap_soi(p))
          end if

       end if

       ! Update snow pack

       if (do_capsnow(c)) then
          h2osno(c) = h2osno(c) - (qmelt(c) + qflx_sub_snow)*dtime
          qflx_snwcp_ice(c) = forc_snow(g) + qflx_dew_snow
       else
          h2osno(c) = h2osno(c) + (forc_snow(g)-qmelt(c)-qflx_sub_snow+qflx_dew_snow)*dtime
          qflx_snwcp_ice(c) = 0._r8
       end if
       h2osno(c) = max(h2osno(c), 0._r8)

#if (defined PERGRO)
       if (abs(h2osno(c)) < 1.e-10_r8) h2osno(c) = 0._r8
#else
       h2osno(c) = max(h2osno(c), 0._r8)
#endif

       ! No snow if lake unfrozen

       if (t_grnd(c) > tfrz) h2osno(c) = 0._r8

       ! Snow depth

       snowdp(c) = h2osno(c)/snow_bd !Assume a constant snow bulk density = 250.

       ! Determine ending water balance

       endwb(c) = h2osno(c)

       ! The following are needed for global average on history tape.
       ! Note that components that are not displayed over lake on history tape
       ! must be set to spval here

       eflx_snomelt(c)   = qmelt(c)*hfus
       qflx_infl(c)      = 0._r8
       qflx_snomelt(c)   = qmelt(c)
       qflx_surf(c)      = 0._r8
       qflx_drain(c)     = 0._r8
       qflx_irrig(c)     = 0._r8
       rootr_column(c,:) = spval
       snowice(c)        = spval
       snowliq(c)        = spval
       soilalpha(c)      = spval
       zwt(c)            = spval
       fcov(c)           = spval
       fsat(c)           = spval
       qcharge(c)        = spval
       h2osoi_vol(c,:)   = spval
       h2osoi_ice(c,:)   = spval
       h2osoi_liq(c,:)   = spval
       qflx_qrgwl(c)     = forc_rain(g) + forc_snow(g) - qflx_evap_tot(p) - qflx_snwcp_ice(c) - &
                           (endwb(c)-begwb(c))/dtime
       qflx_runoff(c)    = qflx_drain(c) + qflx_surf(c) + qflx_qrgwl(c)

       ! The pft average must be done here for output to history tape

       qflx_evap_tot_col(c) = qflx_evap_tot(p)

       !-------------------
       ! added by Jing Chen Oct 22 2012
       h2osno_EASS(c)         = h2osno(c)
       endwb_EASS(c)          = endwb(c)
       snowdp_EASS(c)         = snowdp(c)
       snowice_EASS(c)        = snowice(c)
       snowliq_EASS(c)        = snowliq(c)
       eflx_snomelt_EASS(c)   = eflx_snomelt(c)
       qflx_infl_EASS(c)      = qflx_infl(c)
       qflx_snomelt_EASS(c)   = qflx_snomelt(c)
       qflx_surf_EASS(c)      = qflx_surf(c)
       qflx_drain_EASS(c)     = qflx_drain(c)
       qflx_qrgwl_EASS(c)     = qflx_qrgwl(c)
       qflx_runoff_EASS(c)    = qflx_runoff(c)
       zwt_EASS(c)            = zwt(c)
       qcharge_EASS(c)        = qcharge(c)
       rootr_column_EASS(c,:) = rootr_column(c,:)
       h2osoi_vol_EASS(c,:)   = h2osoi_vol(c,:)
       h2osoi_ice_EASS(c,:)   = h2osoi_ice(c,:)
       h2osoi_liq_EASS(c,:)   = h2osoi_liq(c,:)
       qflx_snwcp_ice_EASS(c) = qflx_snwcp_ice(c)
       !------------------

    end do
!#    write (iulog,*) 'HydrologyLake has finished'

  end subroutine HydrologyLake

end module HydrologyLakeMod
