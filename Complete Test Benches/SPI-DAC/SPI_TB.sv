/////////////////////   Transaction     ///////////////////////

class transaction;
    rand bit [11:0] din;
    rand bit enable;
    bit CS,MOSI;

    function void display(input string tag);
        $display("[%s]: ENABLE : %0b \t DIN : %0d \t CS : %0b \t MOSI : %0b",tag,enable,din,CS,MOSI);
    endfunction

    function transaction copy();
        copy = new();
        copy.din = this.din;
        copy.enable = this.enable;
        copy.CS = this.CS;
        copy.MOSI = this.MOSI;
    endfunction

endclass

/////////////////////   Generator     ///////////////////////

class generator;

    transaction tr;
    mailbox #(transaction) GD_mbx;  //Generator <--> Driver Mailbox
    int count = 0;
    event DRV_next;
    event SCO_next;
    event done;

        function new(mailbox #(transaction) GD_mbx);
            tr = new();
            this.GD_mbx = GD_mbx;
        endfunction

        task main();
            repeat(count) begin
                assert(tr.randomize) else $error("Randomization failed at %0t",$time);
                GD_mbx.put(tr.copy);

                tr.display("GEN");
                @(DRV_next);
                @(SCO_next);
            end
            -> done;
        endtask
endclass

/////////////////////   Driver     ///////////////////////

class driver;
    virtual spiDAC_if vif;  //Virtual interface for DUT 
    transaction tr;
    mailbox #(transaction) GD_mbx;  // Generator <--> Driver Mailbox
    mailbox #(bit [11:0]) DS_mbx;  // Driver <--> Scoreboard Mailbox to check if DUT data is accurate

    event DRV_next;

    function new(mailbox #(transaction) GD_mbx, mailbox #(bit [11:0]) DS_mbx);
        this.GD_mbx = GD_mbx;
        this.DS_mbx = DS_mbx;
    endfunction

    task DUT_reset();
        vif.reset <= 1'b1;
        vif.CS <= 1'b1;
        vif.enable <= 1'b0;
        vif.din <= 12'b0;
        vif.MOSI <= 1'b0;

        repeat(10) @(posedge vif.clk);
            vif.reset <= 1'b0;
        repeat(5) @(posedge vif.clk);
        $display("[DRV] : DUT RESET APPLIED");
    endtask




    task main();

        forever begin 
            GD_mbx.get(tr);
            @(posedge vif.SCLK);

            vif.enable <= 1'b1;
            vif.din <= tr.din;
            DS_mbx.put(tr.din); //send the transmitted data to the SCO

            @(posedge vif.SCLK);

            vif.enable <= 1'b0; 

            wait (vif.CS == 1'b1); //wait until DUT chip select returns high so we know transmission is complete
            $display("[DRV] : DATA SENT TO DAC : %0d",tr.din);
            ->DRV_next;
        end

    endtask

endclass

/////////////////////   Monitor    ///////////////////////

class monitor;

    virtual spiDAC_if vif;
    transaction tr;
    mailbox #(bit [11:0]) MS_mbx; // Monitor <--> Scoreboard mailbox
    bit [11:0] rx_data;

        function new(mailbox #(bit [11:0]) MS_mbx);
            this.MS_mbx = MS_mbx;
        endfunction

    task main();
        forever begin
            @(posedge vif.SCLK);
            wait(vif.CS == 1'b0); // Start of data sending 
            @(posedge vif.SCLK);

                for (int i = 0; i < 12; i ++) begin
                    @(posedge vif.SCLK);
                    rx_data[i] = vif.MOSI;
                end
            wait(vif.CS == 1'b1);   //Full "byte" sent

            $display("[MON] : DATA RCVD FROM DUT : %0d",rx_data);
            MS_mbx.put(rx_data);
        end
    endtask
endclass

/////////////////////   Scoreboard      //////////////////////

class scoreboard;
    mailbox #(bit [11:0]) DS_mbx, MS_mbx;   //Mailboxes to receive expected data vs. ACTUAL data

    bit [11:0] sent_data;
    bit [11:0] rcvd_data;
    event SCO_next;

         function new(mailbox #(bit [11:0]) DS_mbx, MS_mbx);
            this.DS_mbx = DS_mbx;
            this.MS_mbx = MS_mbx;
        endfunction



    task main();
        forever begin
            DS_mbx.get(sent_data);
            MS_mbx.get(rcvd_data);

            $display("[SCO] : DRV DATA : %0d \t MON DATA : %0d",sent_data,rcvd_data);

                if(sent_data == rcvd_data)
                    $display("[SCO] : DATA MATCHED");
                else
                    $display("[SCO] : DATA MISMATCHED");
            
            ->SCO_next;
        end
    endtask

endclass

/////////////////////   Environment     //////////////////////

class environment;
    virtual spiDAC_if vif;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard sco;
    transaction tr;

    event DRV_next;
    event SCO_next;
    


    mailbox #(transaction) GD_mbx;
    mailbox #(bit [11:0]) DS_mbx;
    mailbox #(bit [11:0]) MS_mbx;

        function new(virtual spiDAC_if vif);

        
            GD_mbx = new();       // Constructing mailboxes
            DS_mbx = new();
            MS_mbx = new();
            
            gen = new(GD_mbx);        // Connecting mailboxes 
            drv = new(GD_mbx,DS_mbx);
            mon = new(MS_mbx);
            sco = new(DS_mbx,MS_mbx);

            this.vif = vif;
            drv.vif = this.vif;            // Connecting interfaces 
            mon.vif = this.vif;

            gen.DRV_next = DRV_next;    // Synchronizing Events 
            drv.DRV_next = DRV_next;

            gen.SCO_next = SCO_next;
            sco.SCO_next = SCO_next;
            
            
        endfunction

        task pre_test();
            drv.DUT_reset();
        endtask

        task test();
            fork
                gen.main();
                drv.main();
                mon.main();
                sco.main();
            join_none
        endtask

        task post_test();
            wait(gen.done.triggered);
            $finish();
        endtask

        task main();
            pre_test();
            test();
            post_test();
        endtask
endclass


/////////////////////   Testbench Top     //////////////////////

module SPI_DAC_TB();

spiDAC_if vif();
environment env;

spiDAC DUT(
    .clk(vif.clk),
    .enable(vif.enable),
    .reset(vif.reset),
    .din(vif.din),

    .SCLK(vif.SCLK),
    .CS(vif.CS),
    .MOSI(vif.MOSI)
);

    initial begin
        vif.clk <= 1'b0;
    end

always #5 vif.clk <= ~vif.clk;

initial begin
    env = new(vif);
    env.gen.count = 20;
    env.main();
end

initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
end

endmodule






