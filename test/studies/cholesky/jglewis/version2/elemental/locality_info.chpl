module locality_info {

  proc my_local_cyclic_data ( A_domain, A_grid_domain, processor : 2*int ) {

    const r                = A_grid_domain.high (1) + 1;
    const c                = A_grid_domain.high (2) + 1;

    const my_processor_row = processor (1);
    const my_processor_col = processor (2);

    // this processor owns data with indices in the tensor product
    // [ my_rows, my_cols ];

    const my_rows = A_domain.dim(1).low + my_processor_row .. 
                    A_domain.dim(1).high  by  r;
    const my_cols = A_domain.dim(2).low + my_processor_col .. 
                    A_domain.dim(2).high  by  c;

    // rows it computes of L21

    const my_L21_rows_to_compute =
      A_domain.dim(1).low + my_processor_row + r*my_processor_col .. 
      A_domain.dim(1).high  by  r*c;

    return ( my_rows, my_cols, my_L21_rows_to_compute );
  }

}

